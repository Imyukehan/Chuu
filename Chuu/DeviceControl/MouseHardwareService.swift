import Foundation
import IOKit.hid

enum MouseHardwareService {
    static func scan() throws -> [MouseSnapshot] {
        try MouseDeviceDiscovery.withDevices { devices in
            var seen = Set<String>()
            return devices.compactMap { device -> MouseSnapshot? in
                let model = MouseDeviceDiscovery.model(device)
                if model == "generic" {
                    guard let snapshot = MouseDeviceDiscovery.genericSnapshot(device), seen.insert(snapshot.id).inserted else { return nil }
                    return snapshot
                }
                guard let registration = MouseAdapterRegistry.adapter(for: MouseDeviceDiscovery.identity(device)),
                      seen.insert(MouseDeviceDiscovery.id(device)).inserted else { return nil }
                return snapshot(id: MouseDeviceDiscovery.id(device), descriptor: registration.descriptor) {
                    try registration.make(MouseHIDChannel(device: device)).readBattery()
                }
            }.sorted { ($0.model == "generic" ? 1 : 0, $0.id) < ($1.model == "generic" ? 1 : 0, $1.id) }
        }
    }

    static func snapshot(id: String, descriptor: MouseAdapterDescriptor,
                         read: () throws -> MouseBatteryReading) -> MouseSnapshot? {
        var snapshot = MouseSnapshot(id: id, model: descriptor.model, name: descriptor.name,
                                     battery: nil, charging: false, online: false, updatedAt: Date(),
                                     transport: descriptor.transport)
        do {
            let reading = try read()
            if let value = reading.percentage, !(0...100).contains(value) { throw MouseHardwareError.malformed }
            snapshot.name = reading.name
            snapshot.battery = reading.percentage
            snapshot.charging = reading.charging
            snapshot.online = true
        } catch MouseHardwareError.unsupported {
            return nil
        } catch {
            NSLog("Chuu read %@: %@", snapshot.id, error.localizedDescription)
        }
        return snapshot
    }

    private static func withG502<T>(id: String, _ body: (G502MouseAdapter) throws -> T) throws -> T {
        try MouseDeviceDiscovery.withDevices { devices in
            guard let device = devices.first(where: { !MouseDeviceDiscovery.isMouseInterface($0) && MouseDeviceDiscovery.id($0) == id }),
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
