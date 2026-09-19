import Foundation
import IOKit.hid

enum MouseHardwareError: LocalizedError {
    case unavailable, timedOut, malformed, unsupported, profileChanged, verificationFailed, rollbackFailed
    case io(IOReturn)

    var errorDescription: String? {
        let key: String
        switch self {
        case .unavailable: key = "Mouse unavailable"
        case .timedOut: key = "Mouse did not respond"
        case .malformed: key = "Invalid device response"
        case .unsupported: key = "This profile is not supported"
        case .profileChanged: key = "Profile changed. Refresh and try again."
        case .verificationFailed: key = "Write failed; original profile restored"
        case .rollbackFailed: key = "Write verification failed. Restore the saved backup before continuing."
        case .io(let code): return String(format: "HID: 0x%08X", code)
        }
        return NSLocalizedString(key, tableName: "Chuu", comment: "Hardware operation error")
    }
}

// Each channel lives on one serial worker for its entire run-loop transaction.
final class MouseHIDChannel: MouseReportTransport {
    let device: IOHIDDevice
    private let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    private var response: [UInt8]?
    private var matches: (([UInt8]) -> Bool)?
    private var sequence: UInt8 = 8

    init(device: IOHIDDevice) throws {
        self.device = device
        buffer.initialize(repeating: 0, count: 64)
        let result = IOHIDDeviceOpen(device, 0)
        guard result == kIOReturnSuccess else {
            buffer.deinitialize(count: 64)
            buffer.deallocate()
            throw MouseHardwareError.io(result)
        }
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, _, _, _, bytes, count in
            guard result == kIOReturnSuccess, let context, count > 0, count <= 64 else { return }
            let channel = Unmanaged<MouseHIDChannel>.fromOpaque(context).takeUnretainedValue()
            let report = Array(UnsafeBufferPointer(start: bytes, count: count))
            if channel.matches?(report) == true { channel.response = report }
        }, Unmanaged.passUnretained(self).toOpaque())
        IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
    }

    deinit {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
        IOHIDDeviceClose(device, 0)
        buffer.deinitialize(count: 64)
        buffer.deallocate()
    }

    func exchange(_ packet: [UInt8], reportID: UInt32, matching: @escaping ([UInt8]) -> Bool) throws -> [UInt8] {
        response = nil
        matches = matching
        defer { matches = nil; response = nil }
        let result = packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, Int(reportID), $0.baseAddress!, $0.count)
        }
        guard result == kIOReturnSuccess else { throw MouseHardwareError.io(result) }
        let deadline = CFAbsoluteTimeGetCurrent() + 1.5
        while response == nil && CFAbsoluteTimeGetCurrent() < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, false)
        }
        guard let response else { throw MouseHardwareError.timedOut }
        return response
    }

    func query(feature: UInt8, function: UInt8, payload: [UInt8] = [], long: Bool = false) throws -> [UInt8] {
        guard payload.count <= (long ? 16 : 3) else { throw MouseHardwareError.malformed }
        sequence = sequence % 15 + 1
        let command = function << 4 | sequence
        var packet: [UInt8] = [long ? 0x11 : 0x10, 1, feature, command]
        packet += payload
        packet += Array(repeating: 0, count: (long ? 20 : 7) - packet.count)
        let response = try exchange(packet, reportID: UInt32(packet[0])) { bytes in
            guard bytes.count >= 7, [0x10, 0x11].contains(bytes[0]), bytes[1] == 1 else { return false }
            return (bytes[2] == feature && bytes[3] == command) ||
                ([0x8F, 0xFF].contains(bytes[2]) && bytes[3] == feature && bytes[4] == command)
        }
        guard response[2] == feature else { throw MouseHardwareError.unsupported }
        return Array(response.dropFirst(4))
    }

    func feature(_ id: UInt16) throws -> UInt8 {
        let value = try query(feature: 0, function: 0, payload: [UInt8(id >> 8), UInt8(id & 255)])
        guard let index = value.first, index != 0 else { throw MouseHardwareError.unsupported }
        return index
    }
}

enum MouseDeviceDiscovery {
    static let matches: [[String: Int]] = MouseAdapterRegistry.adapters.flatMap { entry in
        entry.descriptor.interfaces.map { identity in
            [kIOHIDVendorIDKey: identity.vendorID, kIOHIDProductIDKey: identity.productID,
             kIOHIDPrimaryUsagePageKey: identity.usagePage, kIOHIDPrimaryUsageKey: identity.usage]
        }
    } + [[kIOHIDPrimaryUsagePageKey: 1, kIOHIDPrimaryUsageKey: 2]]

    static func identity(_ device: IOHIDDevice) -> MouseHIDIdentity {
        func value(_ key: String) -> Int { IOHIDDeviceGetProperty(device, key as CFString) as? Int ?? 0 }
        return MouseHIDIdentity(vendorID: value(kIOHIDVendorIDKey), productID: value(kIOHIDProductIDKey),
                                usagePage: value(kIOHIDPrimaryUsagePageKey), usage: value(kIOHIDPrimaryUsageKey))
    }

    static func withDevices<T>(_ body: ([IOHIDDevice]) throws -> T) throws -> T {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let result = IOHIDManagerOpen(manager, 0)
        guard result == kIOReturnSuccess else { throw MouseHardwareError.io(result) }
        defer { IOHIDManagerClose(manager, 0) }
        return try body(Array(IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []))
    }

    static func model(_ device: IOHIDDevice) -> String {
        MouseAdapterRegistry.model(for: identity(device))
    }

    static func id(_ device: IOHIDDevice) -> String {
        let location = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
        if model(device) == "generic" {
            let vendor = IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int ?? 0
            let product = IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? Int ?? 0
            let serial = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String ?? ""
            var registryID: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(IOHIDDeviceGetService(device), &registryID)
            return "generic-\(vendor)-\(product)-\(serial.isEmpty ? String(location == 0 ? registryID : UInt64(location)) : serial)"
        }
        return "\(model(device))-\(location)"
    }

    static func isMouseInterface(_ device: IOHIDDevice) -> Bool {
        (IOHIDDeviceGetProperty(device, kIOHIDPrimaryUsagePageKey as CFString) as? Int) == 1
    }

    static func genericSnapshot(_ device: IOHIDDevice) -> MouseSnapshot? {
        let name = IOHIDDeviceGetProperty(device, kIOHIDProductKey as CFString) as? String ?? "Mouse"
        let builtIn = IOHIDDeviceGetProperty(device, "Built-In" as CFString) as? Bool ?? false
        let transport = IOHIDDeviceGetProperty(device, kIOHIDTransportKey as CFString) as? String ?? "USB"
        guard isGenericMouse(name: name, builtIn: builtIn, transport: transport) else { return nil }
        return MouseSnapshot(id: id(device), model: "generic", name: name, battery: nil,
                             charging: false, online: true, updatedAt: Date(),
                             transport: transport.hasPrefix("Bluetooth") ? "Bluetooth" : transport)
    }

    static func isGenericMouse(name: String, builtIn: Bool, transport: String) -> Bool {
        !builtIn && !["trackpad", "keyboard", "virtual", "touchpad", "receiver"].contains(where: {
            name.localizedCaseInsensitiveContains($0)
        }) && ["USB", "Bluetooth", "Bluetooth Low Energy"].contains(transport)
    }
}

// Hot-plug prompts a read; radio wake and battery changes still use the low-rate poll.
final class MouseConnectionWatcher {
    private let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
    var onChange: ((String, Bool) -> Void)?

    init() {
        IOHIDManagerSetDeviceMatchingMultiple(manager, MouseDeviceDiscovery.matches as CFArray)
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, { context, result, _, device in
            guard result == kIOReturnSuccess, let context else { return }
            Unmanaged<MouseConnectionWatcher>.fromOpaque(context).takeUnretainedValue()
                .onChange?(MouseDeviceDiscovery.id(device), true)
        }, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, { context, result, _, device in
            guard result == kIOReturnSuccess, let context else { return }
            Unmanaged<MouseConnectionWatcher>.fromOpaque(context).takeUnretainedValue()
                .onChange?(MouseDeviceDiscovery.id(device), false)
        }, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerOpen(manager, 0)
    }

    deinit {
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, 0)
    }
}
