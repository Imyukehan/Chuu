import Foundation
import IOKit.hid

enum MouseHardwareService {
    static func scan() throws -> [MouseSnapshot] {
        try MouseDeviceDiscovery.withDevices { devices in
            devices.compactMap { device in
                let model = MouseDeviceDiscovery.model(device)
                var snapshot = MouseSnapshot(id: MouseDeviceDiscovery.id(device), model: model,
                                             name: model == "g502x" ? "G502 X PLUS" : "MCHOSE G7",
                                             battery: nil, charging: false, online: false, updatedAt: Date())
                do {
                    let channel = try MouseHIDChannel(device: device)
                    if model == "g502x" {
                        let adapter = G502MouseAdapter(channel: channel)
                        snapshot.name = try adapter.name()
                        let reading = try adapter.battery()
                        snapshot.battery = reading.0
                        snapshot.charging = reading.1
                    } else {
                        var packet: [UInt8] = [0x55,0x30,0xA5,0x0B,0x2E,1,1,1]
                        packet += Array(repeating: 0, count: 56)
                        let bytes = try channel.exchange(packet, reportID: 0) { report in
                            report.count >= 10 && Array(report.prefix(8)) == [0xAA,0x30,0xA5,0x0B,0x0A,1,1,1]
                        }
                        guard bytes[8] <= 100 else { throw MouseHardwareError.malformed }
                        snapshot.battery = Int(bytes[8])
                        snapshot.charging = bytes[9] != 0
                    }
                    snapshot.online = true
                } catch MouseHardwareError.unsupported {
                    return nil
                } catch {
                    NSLog("MouseControl read %@: %@", snapshot.id, error.localizedDescription)
                }
                return snapshot
            }.sorted { $0.id < $1.id }
        }
    }

    private static func withG502<T>(id: String, _ body: (G502MouseAdapter) throws -> T) throws -> T {
        try MouseDeviceDiscovery.withDevices { devices in
            guard let device = devices.first(where: { MouseDeviceDiscovery.id($0) == id }),
                  MouseDeviceDiscovery.model(device) == "g502x" else { throw MouseHardwareError.unavailable }
            return try body(G502MouseAdapter(channel: MouseHIDChannel(device: device)))
        }
    }

    static func profile(id: String) throws -> OnboardMouseProfile {
        try withG502(id: id) { try $0.profile(deviceID: id) }
    }

    static func save(_ profile: OnboardMouseProfile, button: Int?, mapping: [UInt8]?, lightingEnabled: Bool?) throws -> OnboardMouseProfile {
        try withG502(id: profile.deviceID) { try $0.save(profile, button: button, mapping: mapping, lightingEnabled: lightingEnabled) }
    }
}
