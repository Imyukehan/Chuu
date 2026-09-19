// Test-only example. This invented protocol is not safe to send to a real mouse.
import Foundation
@testable import Chuu

final class ExampleMouseAdapter: MouseBatteryAdapter {
    static let descriptor = MouseAdapterDescriptor(
        model: "example-mouse", vendor: "Example", name: "Example Mouse", transport: "2.4 GHz",
        interfaces: [.init(vendorID: 0, productID: 0, usagePage: 0xFF00, usage: 1)])

    private let channel: any MouseReportTransport
    init(channel: any MouseReportTransport) { self.channel = channel }

    static func decode(_ bytes: [UInt8]) throws -> MouseBatteryReading {
        guard bytes.count == 3, bytes[0] == 0xBA, bytes[1] <= 100, bytes[2] <= 1 else {
            throw MouseHardwareError.malformed
        }
        return MouseBatteryReading(name: descriptor.name, percentage: Int(bytes[1]), charging: bytes[2] == 1)
    }

    func readBattery() throws -> MouseBatteryReading {
        let bytes = try channel.exchange([0xBA, 0], reportID: 0) { $0.count == 3 && $0[0] == 0xBA }
        return try Self.decode(bytes)
    }
}
