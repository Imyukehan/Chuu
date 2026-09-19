import Foundation

struct MouseSnapshot: Codable, Equatable, Identifiable {
    var id: String
    var model: String
    var name: String
    var battery: Int?
    var charging: Bool
    var online: Bool
    var updatedAt: Date

    var imageName: String { model == "g502x" ? "G502Top" : "G7" }
    func isFresh(at date: Date) -> Bool { date.timeIntervalSince(updatedAt) < 30 * 60 }
}

struct MouseSnapshotFile: Codable {
    var devices: [MouseSnapshot]
    var writtenAt: Date
}

enum MouseSnapshotStore {
    static let group = "MA4UNJ3J25.moe.khan.MouseControl"
    static let widgetKind = "MouseBatteryWidget"

    static var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group)?
            .appendingPathComponent("mouse-batteries.json")
    }

    static func read() -> MouseSnapshotFile? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(MouseSnapshotFile.self, from: data)
    }

    static func write(_ devices: [MouseSnapshot]) throws {
        guard let url = fileURL else {
            throw NSError(domain: "MouseControl", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "App Group unavailable"])
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(MouseSnapshotFile(devices: devices, writtenAt: Date()))
        try data.write(to: url, options: .atomic)
    }
}
