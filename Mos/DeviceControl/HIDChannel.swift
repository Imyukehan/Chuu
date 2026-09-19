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
        return NSLocalizedString(key, tableName: "MouseControl", comment: "Hardware operation error")
    }
}

// Each channel lives on one serial worker for its entire run-loop transaction.
final class MouseHIDChannel {
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
    static func withDevices<T>(_ body: ([IOHIDDevice]) throws -> T) throws -> T {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        let matches: [[String: Int]] = [
            [kIOHIDVendorIDKey: 0x046D, kIOHIDProductIDKey: 0xC547,
             kIOHIDPrimaryUsagePageKey: 0xFF00, kIOHIDPrimaryUsageKey: 1],
            [kIOHIDVendorIDKey: 0xA8A5, kIOHIDProductIDKey: 0x2255,
             kIOHIDPrimaryUsagePageKey: 0xFF01, kIOHIDPrimaryUsageKey: 0x10]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matches as CFArray)
        let result = IOHIDManagerOpen(manager, 0)
        guard result == kIOReturnSuccess else { throw MouseHardwareError.io(result) }
        defer { IOHIDManagerClose(manager, 0) }
        return try body(Array(IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? []))
    }

    static func model(_ device: IOHIDDevice) -> String {
        (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? Int) == 0x046D ? "g502x" : "g7"
    }

    static func id(_ device: IOHIDDevice) -> String {
        let location = IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? Int ?? 0
        return "\(model(device))-\(location)"
    }
}
