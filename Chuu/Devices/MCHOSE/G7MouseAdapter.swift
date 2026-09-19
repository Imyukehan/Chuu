import Foundation

final class G7MouseAdapter: MouseBatteryAdapter {
    static let descriptor = MouseAdapterDescriptor(
        model: "g7", vendor: "MCHOSE", name: "MCHOSE G7", transport: "2.4 GHz",
        interfaces: [.init(vendorID: 0xA8A5, productID: 0x2255, usagePage: 0xFF01, usage: 0x10)])

    private let channel: any MouseReportTransport
    init(channel: any MouseReportTransport) { self.channel = channel }

    static var batteryRequest: [UInt8] {
        [0x55, 0x30, 0xA5, 0x0B, 0x2E, 1, 1, 1] + Array(repeating: 0, count: 56)
    }

    private static func isBatteryResponse(_ bytes: [UInt8]) -> Bool {
        bytes.count >= 10 && Array(bytes.prefix(8)) == [0xAA, 0x30, 0xA5, 0x0B, 0x0A, 1, 1, 1]
    }

    static func decodeBattery(_ bytes: [UInt8]) throws -> MouseBatteryReading {
        guard isBatteryResponse(bytes), bytes[8] <= 100 else { throw MouseHardwareError.malformed }
        return MouseBatteryReading(name: descriptor.name, percentage: Int(bytes[8]), charging: bytes[9] != 0)
    }

    func readBattery() throws -> MouseBatteryReading {
        try Self.decodeBattery(channel.exchange(Self.batteryRequest, reportID: 0, matching: Self.isBatteryResponse))
    }
}
