import Foundation

struct MouseAlertPolicy {
    enum Event: Equatable {
        case connected(String)
        case lowBattery(String)
    }

    var warnedDevices: Set<String> = []
    private var initialized = false
    private var suppressInitialOffline = false
    private var presentDevices: Set<String> = []
    private var pendingConnections: Set<String> = []
    private var lastConnectionAlert: [String: Date] = [:]

    mutating func rebaseline() {
        initialized = false
        suppressInitialOffline = true
        pendingConnections.removeAll()
    }

    mutating func didNotifyLowBattery(_ id: String) { warnedDevices.insert(id) }
    mutating func deviceRemoved(_ id: String) {
        presentDevices.remove(id)
        pendingConnections.remove(id)
    }

    mutating func consume(_ devices: [MouseSnapshot], at now: Date, lowBatteryEnabled: Bool) -> [Event] {
        var events: [Event] = []
        let present = Set(devices.map(\.id))
        pendingConnections.formIntersection(present)
        // Receiver presence, not a failed radio query, defines a new connection.
        // A radio sleeping behind an attached receiver cannot be distinguished from power-off.
        if initialized { pendingConnections.formUnion(present.subtracting(presentDevices)) }
        else { pendingConnections = suppressInitialOffline ? [] : Set(devices.filter { !$0.online }.map(\.id)) }
        for device in devices where device.online {
            if initialized, pendingConnections.remove(device.id) != nil,
               now.timeIntervalSince(lastConnectionAlert[device.id] ?? .distantPast) >= 300 {
                events.append(.connected(device.id))
                lastConnectionAlert[device.id] = now
            }
            guard let battery = device.battery, (0...100).contains(battery), device.isFresh(at: now) else { continue }
            if battery >= 25 { warnedDevices.remove(device.id) }
            if lowBatteryEnabled, battery <= 20, !device.charging, !warnedDevices.contains(device.id) {
                events.append(.lowBattery(device.id))
            }
        }
        presentDevices = present
        initialized = true
        return events
    }
}
