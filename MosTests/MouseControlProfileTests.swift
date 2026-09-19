import XCTest
@testable import Mos_Debug

final class MouseControlProfileTests: XCTestCase {
    private func fixture() throws -> OnboardMouseProfile {
        var bytes = [UInt8](repeating: 0, count: 255)
        for (index, mapping) in OnboardMouseProfile.defaults.enumerated() {
            bytes.replaceSubrange((32 + index * 4)..<(36 + index * 4), with: mapping)
        }
        bytes[208] = 0x0F
        let crc = OnboardMouseProfile.crc(bytes)
        bytes[253] = UInt8(crc >> 8)
        bytes[254] = UInt8(crc & 255)
        return try OnboardMouseProfile(deviceID: "test", sector: 1, dpiIndex: 4, bytes: bytes)
    }

    func testCRCMatchesKnownVector() {
        XCTAssertEqual(OnboardMouseProfile.crc(Array("123456789".utf8) + [0, 0]), 0x29B1)
    }

    func testSniperMappingOnlyChangesTargetAndChecksum() throws {
        let original = try fixture()
        let edited = try original.edited(button: 4, mapping: OnboardMouseProfile.mouseMappings[5])
        XCTAssertEqual(Array(edited[48..<52]), [0x80, 1, 0, 32])
        for index in 0..<253 where !(48..<52).contains(index) {
            XCTAssertEqual(edited[index], original.bytes[index])
        }
        XCTAssertNoThrow(try OnboardMouseProfile(deviceID: "test", sector: 1, dpiIndex: 4, bytes: edited))
    }

    func testLightingEditPreservesEveryOtherField() throws {
        let original = try fixture()
        let edited = try original.edited(lighting: Array(repeating: 0, count: 45))
        XCTAssertEqual(Array(edited[..<208]), Array(original.bytes[..<208]))
        let profile = try OnboardMouseProfile(deviceID: "test", sector: 1, dpiIndex: 4, bytes: edited)
        XCTAssertTrue(profile.lightsOff)
    }

    func testLightingOnOffRoundTripPreservesButtonsAndDPI() throws {
        let original = try fixture()
        let offBytes = try original.edited(lighting: Array(repeating: 0, count: 45))
        let off = try OnboardMouseProfile(deviceID: "test", sector: 1, dpiIndex: 4, bytes: offBytes)
        let onBytes = try off.edited(lighting: original.lighting)
        XCTAssertEqual(onBytes, original.bytes)
        XCTAssertEqual(try off.edited(), off.bytes)
    }

    func testDefaultLightingMatchesOriginalG502EffectLayout() throws {
        let original = try fixture()
        let bytes = try original.edited(lighting: OnboardMouseProfile.defaultLighting)
        let on = try OnboardMouseProfile(deviceID: "test", sector: 1, dpiIndex: 4, bytes: bytes)
        XCTAssertFalse(on.lightsOff)
        XCTAssertEqual([208, 219, 230, 241].map { bytes[$0] }, [0x0F, 0x0F, 0x10, 0x10])
        XCTAssertEqual(bytes[252], 3)
        XCTAssertEqual(Array(bytes[..<208]), Array(original.bytes[..<208]))
        XCTAssertThrowsError(try original.edited(lighting: [1, 2, 3]))
    }

    func testRestoresOnlyMatchingValidLightingBackup() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let original = try fixture()
        XCTAssertEqual(try G502MouseAdapter.restoredLighting(for: original, from: folder), OnboardMouseProfile.defaultLighting)
        try Data(original.bytes).write(to: folder.appendingPathComponent("other-profile1-old.bin"))
        try Data(original.bytes).write(to: folder.appendingPathComponent("test-profile2-old.bin"))
        try Data([0, 1, 2]).write(to: folder.appendingPathComponent("test-profile1-corrupt.bin"))
        XCTAssertEqual(try G502MouseAdapter.restoredLighting(for: original, from: folder), OnboardMouseProfile.defaultLighting)
        try Data(original.bytes).write(to: folder.appendingPathComponent("test-profile1-valid.bin"))
        let off = try original.edited(lighting: Array(repeating: 0, count: 45))
        try Data(off).write(to: folder.appendingPathComponent("test-profile1-off.bin"))
        XCTAssertEqual(try G502MouseAdapter.restoredLighting(for: original, from: folder), original.lighting)
    }

    func testRejectsCorruptionAndPrimaryButtonChanges() throws {
        let original = try fixture()
        var corrupt = original.bytes
        corrupt[100] ^= 1
        XCTAssertThrowsError(try OnboardMouseProfile(deviceID: "test", sector: 1, dpiIndex: 4, bytes: corrupt))
        XCTAssertThrowsError(try original.edited(button: 0, mapping: [0x80,1,0,2]))
        XCTAssertThrowsError(try original.edited(button: 20, mapping: [0x80,1,0,2]))
        XCTAssertThrowsError(try original.edited(button: 4, mapping: [0,0,0,0]))
    }

    func testSnapshotRoundTripAndStaleness() throws {
        let now = Date(timeIntervalSince1970: 100000)
        let device = MouseSnapshot(id: "test", model: "g502x", name: "G502 X PLUS", battery: 83,
                                   charging: false, online: true, updatedAt: now)
        let data = try JSONEncoder().encode(device)
        XCTAssertEqual(try JSONDecoder().decode(MouseSnapshot.self, from: data), device)
        XCTAssertTrue(device.isFresh(at: now.addingTimeInterval(1799)))
        XCTAssertFalse(device.isFresh(at: now.addingTimeInterval(1800)))
    }
}
