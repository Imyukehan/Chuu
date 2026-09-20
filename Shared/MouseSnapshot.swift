import Foundation
import Security

struct MouseSnapshot: Codable, Equatable, Identifiable {
    var id: String
    var model: String
    var name: String
    var battery: Int?
    var charging: Bool
    var online: Bool
    var updatedAt: Date
    var transport: String? = nil

    var imageName: String { model == "g502x" ? "G502Top" : model == "g7" ? "G7" : "" }
    var connectionLabel: String { transport ?? (["g502x", "g7"].contains(model) ? "2.4 GHz" : "USB") }
    func isFresh(at date: Date) -> Bool { date.timeIntervalSince(updatedAt) < 30 * 60 }
}

struct MouseSnapshotFile: Codable {
    var devices: [MouseSnapshot]
    var writtenAt: Date
}

enum MouseSnapshotStore {
    enum Destination { case shared, local }

    static let group = "MA4UNJ3J25.moe.khan.MouseControl"
    static let widgetKind = "MouseBatteryWidget"

    // A team-prefixed group is not owned by an ad-hoc-signed process.
    static let canUseSharedStorage: Bool = {
        var code: SecCode?
        var staticCode: SecStaticCode?
        var info: CFDictionary?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code,
              SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let values = info as? [String: Any] else { return false }
        return canUseSharedStorage(teamID: values[kSecCodeInfoTeamIdentifier as String] as? String)
    }()

    static func canUseSharedStorage(teamID: String?) -> Bool {
        guard let teamID, !teamID.isEmpty else { return false }
        return teamID == group.components(separatedBy: ".").first
    }

    static var fileURL: URL? {
        guard canUseSharedStorage else { return nil }
        return FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("mouse-batteries.json")
    }

    static func read() -> MouseSnapshotFile? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MouseSnapshotFile.self, from: data)
    }

    static func write(_ devices: [MouseSnapshot]) throws -> Destination {
        let localURL = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: false)
            .appendingPathComponent("moe.khan.MouseControl", isDirectory: true)
            .appendingPathComponent("mouse-batteries.json")
        return try write(devices, sharedURL: fileURL, localURL: localURL)
    }

    static func write(_ devices: [MouseSnapshot], sharedURL: URL?, localURL: URL) throws -> Destination {
        let data = try JSONEncoder().encode(MouseSnapshotFile(devices: devices, writtenAt: Date()))
        if let sharedURL {
            do {
                try save(data, to: sharedURL)
                return .shared
            } catch {
                // A widget-container failure must not block the app's own battery cache.
            }
        }
        try save(data, to: localURL)
        return .local
    }

    private static func save(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
