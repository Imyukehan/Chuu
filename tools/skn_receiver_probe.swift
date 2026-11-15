// Read-only protocol queries for the SKN receiver tested on 2026-11-15.
import Foundation
import IOKit.hid

final class SKNProbeReports {
    var values: [[UInt8]] = []
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02x", $0) }.joined(separator: " ")
}

let shouldQuery = CommandLine.arguments.contains("--query")
let manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
IOHIDManagerSetDeviceMatching(manager, [
    kIOHIDVendorIDKey: 0x362d, kIOHIDProductIDKey: 0xd101,
    kIOHIDPrimaryUsagePageKey: 0xff60, kIOHIDPrimaryUsageKey: 0x61
] as CFDictionary)
let opened = IOHIDManagerOpen(manager, 0)
guard opened == kIOReturnSuccess else {
    print("Manager open failed:", String(format: "0x%08x", opened))
    exit(1)
}
defer { IOHIDManagerClose(manager, 0) }
let devices = Array(IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> ?? [])
print("Matching SKN receiver configuration interfaces:", devices.count)
guard shouldQuery else {
    print("Use --query to send the documented read-only queries. No queries sent.")
    exit(0)
}

for device in devices {
    let result = IOHIDDeviceOpen(device, 0)
    guard result == kIOReturnSuccess else {
        print("Device open failed:", String(format: "0x%08x", result))
        continue
    }
    let reports = SKNProbeReports()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: 64)
    defer {
        IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, nil, nil)
        IOHIDDeviceClose(device, 0)
        buffer.deallocate()
    }
    IOHIDDeviceRegisterInputReportCallback(device, buffer, 64, { context, result, _, _, _, data, length in
        guard result == kIOReturnSuccess, let context else { return }
        Unmanaged<SKNProbeReports>.fromOpaque(context).takeUnretainedValue().values
            .append(Array(UnsafeBufferPointer(start: data, count: length)))
    }, Unmanaged.passUnretained(reports).toOpaque())
    IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

    // Fixed allowlist: no arbitrary commands, profile writes, DFU or resets.
    let requests: [[UInt8]] = [
        [0x01], [0xa0], [0xa1], [0xa2],
        [0xb1], [0xb2], [0xb3], [0xa7, 0x01], [0xa7, 0x0b]
    ]
    for request in requests {
        reports.values.removeAll()
        let packet = request + Array(repeating: UInt8(0), count: 32 - request.count)
        let status = packet.withUnsafeBufferPointer {
            IOHIDDeviceSetReport(device, kIOHIDReportTypeOutput, 0, $0.baseAddress!, $0.count)
        }
        print("Request", hex(request), "status", String(format: "0x%08x", status))
        guard status == kIOReturnSuccess else { continue }
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.05, false)
            if reports.values.contains(where: { $0.first == request.first || $0.first == 0xff }) { break }
        }
        if reports.values.isEmpty { print("No response") }
        for reply in reports.values.prefix(5) { print("Reply", hex(reply)) }
    }
}
