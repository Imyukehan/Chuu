import Foundation

final class G502MouseAdapter: MouseBatteryAdapter {
    static let descriptor = MouseAdapterDescriptor(
        model: "g502x", vendor: "Logitech", name: "G502 X PLUS", transport: "2.4 GHz",
        interfaces: [.init(vendorID: 0x046D, productID: 0xC547, usagePage: 0xFF00, usage: 1)])

    let channel: MouseHIDChannel
    init(channel: MouseHIDChannel) { self.channel = channel }

    func readBattery() throws -> MouseBatteryReading {
        let deviceName = try name()
        let reading = try battery()
        return MouseBatteryReading(name: deviceName, percentage: reading.0, charging: reading.1)
    }

    func name() throws -> String {
        let feature = try channel.feature(0x0005)
        let length = Int(try channel.query(feature: feature, function: 0)[0])
        guard length > 0, length < 100 else { throw MouseHardwareError.malformed }
        var bytes: [UInt8] = []
        while bytes.count < length {
            let part = try channel.query(feature: feature, function: 1, payload: [UInt8(bytes.count)])
            bytes += part.prefix(length - bytes.count)
        }
        guard let name = String(bytes: bytes, encoding: .utf8), name == "G502 X PLUS" else {
            throw MouseHardwareError.unsupported
        }
        return name
    }

    func battery() throws -> (Int, Bool) {
        let feature = try channel.feature(0x1004)
        let capabilities = try channel.query(feature: feature, function: 0)
        guard capabilities[1] & 2 != 0 else { throw MouseHardwareError.unsupported }
        let value = try channel.query(feature: feature, function: 1)
        guard value[0] <= 100 else { throw MouseHardwareError.malformed }
        return (Int(value[0]), (1...3).contains(value[2]))
    }

    private func profileFeature() throws -> UInt8 {
        _ = try name()
        let feature = try channel.feature(0x8100)
        let descriptor = try channel.query(feature: feature, function: 0)
        guard descriptor.count >= 9, descriptor[0] == 1, descriptor[1] == 5,
              descriptor[3] == 5, descriptor[5] == 11,
              descriptor[7] == 0, descriptor[8] == 255 else { throw MouseHardwareError.unsupported }
        let mode = try channel.query(feature: feature, function: 2)
        guard mode[0] == 1 else { throw MouseHardwareError.unsupported }
        return feature
    }

    func profile(deviceID: String) throws -> OnboardMouseProfile {
        let feature = try profileFeature()
        let current = try channel.query(feature: feature, function: 4)
        let sector = Int(current[0]) << 8 | Int(current[1])
        guard (1...5).contains(sector) else { throw MouseHardwareError.unsupported }
        let dpi = try channel.query(feature: feature, function: 11)[0]
        return try OnboardMouseProfile(deviceID: deviceID, sector: sector, dpiIndex: dpi,
                                       bytes: readSector(sector, feature: feature))
    }

    private func readSector(_ sector: Int, feature: UInt8) throws -> [UInt8] {
        var data = [UInt8](repeating: 0, count: 255)
        for position in stride(from: 0, to: 255, by: 16) {
            let offset = min(position, 239)
            let value = try channel.query(feature: feature, function: 5,
                                          payload: [0, UInt8(sector), 0, UInt8(offset)], long: true)
            guard value.count == 16 else { throw MouseHardwareError.malformed }
            data.replaceSubrange(offset..<(offset + 16), with: value)
        }
        return data
    }

    private func writeSector(_ sector: Int, feature: UInt8, data: [UInt8]) throws {
        _ = try channel.query(feature: feature, function: 6,
                              payload: [0, UInt8(sector), 0, 0, 0, 255], long: true)
        for offset in stride(from: 0, to: 255, by: 16) {
            var chunk = Array(data[offset..<min(offset + 16, 255)])
            chunk += Array(repeating: 255, count: 16 - chunk.count)
            _ = try channel.query(feature: feature, function: 7, payload: chunk, long: true)
        }
        _ = try channel.query(feature: feature, function: 8)
    }

    static func restoredLighting(for profile: OnboardMouseProfile, from folder: URL) throws -> [UInt8] {
        let prefix = "\(profile.deviceID)-profile\(profile.sector)-"
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.lastPathComponent.hasPrefix(prefix) && $0.pathExtension == "bin" }
            .sorted {
                let left = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let right = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return left > right
            }
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let saved = try? OnboardMouseProfile(deviceID: profile.deviceID, sector: profile.sector,
                                                       dpiIndex: profile.dpiIndex, bytes: Array(data)),
                  !saved.lightsOff else { continue }
            return saved.lighting
        }
        return OnboardMouseProfile.defaultLighting
    }

    func save(_ expected: OnboardMouseProfile, button: Int?, mapping: [UInt8]?, lightingEnabled: Bool?) throws -> OnboardMouseProfile {
        let fresh = try profile(deviceID: expected.deviceID)
        guard fresh.sector == expected.sector, fresh.bytes == expected.bytes else {
            throw MouseHardwareError.profileChanged
        }
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("moe.khan.MouseControl/Backups", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let lighting: [UInt8]?
        if let lightingEnabled {
            lighting = lightingEnabled ? (fresh.lightsOff ? try Self.restoredLighting(for: fresh, from: folder) : fresh.lighting)
                : Array(repeating: 0, count: 45)
        } else { lighting = nil }
        let bytes = try fresh.edited(button: button, mapping: mapping, lighting: lighting)
        guard bytes != fresh.bytes else { return fresh }
        let backup = folder.appendingPathComponent("\(fresh.deviceID)-profile\(fresh.sector)-\(UUID().uuidString).bin")
        try Data(fresh.bytes).write(to: backup, options: .atomic)
        let file = try FileHandle(forWritingTo: backup)
        file.synchronizeFile()
        file.closeFile()

        let feature = try profileFeature()
        // Recheck the active slot immediately before the first write.
        let current = try channel.query(feature: feature, function: 4)
        guard Int(current[0]) << 8 | Int(current[1]) == fresh.sector else { throw MouseHardwareError.profileChanged }
        do {
            try writeSector(fresh.sector, feature: feature, data: bytes)
            guard try readSector(fresh.sector, feature: feature) == bytes else { throw MouseHardwareError.malformed }
        } catch {
            do {
                try writeSector(fresh.sector, feature: feature, data: fresh.bytes)
                guard try readSector(fresh.sector, feature: feature) == fresh.bytes else { throw MouseHardwareError.malformed }
            } catch { throw MouseHardwareError.rollbackFailed }
            throw MouseHardwareError.verificationFailed
        }
        _ = try channel.query(feature: feature, function: 3, payload: [0, UInt8(fresh.sector), 0])
        if try channel.query(feature: feature, function: 11)[0] != fresh.dpiIndex {
            _ = try channel.query(feature: feature, function: 12, payload: [fresh.dpiIndex])
        }
        return try profile(deviceID: fresh.deviceID)
    }
}
