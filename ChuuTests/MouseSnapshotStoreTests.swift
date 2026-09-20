import Foundation
import XCTest
#if !CHUU_STANDALONE_SNAPSHOT_TESTS
@testable import Chuu
#endif

final class MouseSnapshotStoreTests: XCTestCase {
    private var root: URL!
    private var shared: URL { root.appendingPathComponent("shared/mouse-batteries.json") }
    private var local: URL { root.appendingPathComponent("local/mouse-batteries.json") }
    private var devices: [MouseSnapshot] {
        [MouseSnapshot(id: "fixture", model: "g502x", name: "Test mouse", battery: 73,
                       charging: true, online: true, updatedAt: Date(timeIntervalSince1970: 1234), transport: "2.4 GHz")]
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    private func read(_ url: URL) throws -> MouseSnapshotFile {
        try JSONDecoder().decode(MouseSnapshotFile.self, from: Data(contentsOf: url))
    }

    func testOnlyMatchingTeamCanResolveSharedStorage() {
        XCTAssertTrue(MouseSnapshotStore.canUseSharedStorage(teamID: "MA4UNJ3J25"))
        for team in [nil, "", "OTHERTEAM1", "MA4UNJ3J25.moe"] as [String?] {
            XCTAssertFalse(MouseSnapshotStore.canUseSharedStorage(teamID: team))
        }
    }

    func testSharedStoragePreservesSnapshotAndDoesNotWriteLocalCache() throws {
        XCTAssertEqual(try MouseSnapshotStore.write(devices, sharedURL: shared, localURL: local), .shared)
        XCTAssertEqual(try read(shared).devices, devices)
        XCTAssertFalse(FileManager.default.fileExists(atPath: local.path))
    }

    func testMissingSharedContainerUsesLocalCache() throws {
        XCTAssertEqual(try MouseSnapshotStore.write(devices, sharedURL: nil, localURL: local), .local)
        XCTAssertEqual(try read(local).devices, devices)
    }

    func testDeniedSharedContainerFallsBackThenRecovers() throws {
        try XCTSkipIf(geteuid() == 0, "Root bypasses directory permissions")
        let directory = shared.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path) }
        XCTAssertEqual(try MouseSnapshotStore.write(devices, sharedURL: shared, localURL: local), .local)
        XCTAssertEqual(try read(local).devices, devices)
        XCTAssertFalse(FileManager.default.fileExists(atPath: shared.path))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        XCTAssertEqual(try MouseSnapshotStore.write(devices, sharedURL: shared, localURL: local), .shared)
        XCTAssertEqual(try read(shared).devices, devices)
    }

    func testDisconnectOverwritesLocalCacheWithEmptySnapshot() throws {
        _ = try MouseSnapshotStore.write(devices, sharedURL: nil, localURL: local)
        _ = try MouseSnapshotStore.write([], sharedURL: nil, localURL: local)
        XCTAssertTrue(try read(local).devices.isEmpty)
    }

    func testFailureOfBothStoresIsReportedToCaller() throws {
        let file = root.appendingPathComponent("not-a-directory")
        try Data().write(to: file)
        let invalid = file.appendingPathComponent("mouse-batteries.json")
        XCTAssertThrowsError(try MouseSnapshotStore.write(devices, sharedURL: invalid, localURL: invalid))
    }

    #if CHUU_STANDALONE_SNAPSHOT_TESTS
    func testAdHocProcessDoesNotResolveOrReadAppGroup() {
        XCTAssertFalse(MouseSnapshotStore.canUseSharedStorage)
        XCTAssertNil(MouseSnapshotStore.fileURL)
        XCTAssertNil(MouseSnapshotStore.read())
    }

    #endif
}
