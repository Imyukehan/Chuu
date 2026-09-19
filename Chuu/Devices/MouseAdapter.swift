import Foundation

struct MouseHIDIdentity: Equatable {
    let vendorID: Int
    let productID: Int
    let usagePage: Int
    let usage: Int
}

struct MouseAdapterDescriptor {
    let model: String
    let vendor: String
    let name: String
    let transport: String
    let interfaces: [MouseHIDIdentity]

    func matches(_ identity: MouseHIDIdentity) -> Bool { interfaces.contains(identity) }

    func recognizesProduct(_ identity: MouseHIDIdentity) -> Bool {
        interfaces.contains { $0.vendorID == identity.vendorID && $0.productID == identity.productID }
    }
}

struct MouseBatteryReading: Equatable {
    var name: String
    var percentage: Int?
    var charging: Bool
}

// Adapters only read battery state. Profile writes remain behind model-specific validation.
protocol MouseBatteryAdapter {
    func readBattery() throws -> MouseBatteryReading
}

protocol MouseReportTransport {
    func exchange(_ packet: [UInt8], reportID: UInt32,
                  matching: @escaping ([UInt8]) -> Bool) throws -> [UInt8]
}
