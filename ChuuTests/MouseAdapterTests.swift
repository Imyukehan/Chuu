import XCTest
@testable import Chuu

final class MouseAdapterTests: XCTestCase {
    func testRegistryMatchesExactInterfaceNotJustBrand() throws {
        let g502 = MouseHIDIdentity(vendorID: 0x046D, productID: 0xC547, usagePage: 0xFF00, usage: 1)
        XCTAssertEqual(MouseAdapterRegistry.adapter(for: g502)?.descriptor.model, "g502x")
        XCTAssertEqual(MouseAdapterRegistry.adapter(for: .init(vendorID: 0xA8A5, productID: 0x2255,
                                                               usagePage: 0xFF01, usage: 0x10))?.descriptor.model, "g7")
        XCTAssertNil(MouseAdapterRegistry.adapter(for: .init(vendorID: 0x046D, productID: 0xC547, usagePage: 1, usage: 2)))
        XCTAssertNil(MouseAdapterRegistry.adapter(for: .init(vendorID: 0x046D, productID: 0xFFFF, usagePage: 0xFF00, usage: 1)))
        XCTAssertEqual(MouseAdapterRegistry.model(for: .init(vendorID: 0x046D, productID: 0xC547, usagePage: 1, usage: 2)), "g502x")
    }

    func testRegistryIsUniqueAndExampleIsNeverRegistered() {
        let descriptors = MouseAdapterRegistry.adapters.map(\.descriptor)
        XCTAssertEqual(Set(descriptors.map(\.model)).count, descriptors.count)
        let interfaces = descriptors.flatMap(\.interfaces)
        for identity in interfaces { XCTAssertEqual(interfaces.filter { $0 == identity }.count, 1) }
        XCTAssertFalse(descriptors.contains { $0.model == ExampleMouseAdapter.descriptor.model })
        XCTAssertNil(MouseAdapterRegistry.adapter(for: ExampleMouseAdapter.descriptor.interfaces[0]))
    }

    func testG7RequestAndResponseThroughMockTransport() throws {
        let channel = FixtureMouseTransport(reports: [[0], [0xAA, 0x30, 0xA5, 0x0B, 0x0A, 1, 1, 1, 80, 1]])
        let reading = try G7MouseAdapter(channel: channel).readBattery()
        XCTAssertEqual(reading, MouseBatteryReading(name: "MCHOSE G7", percentage: 80, charging: true))
        XCTAssertEqual(channel.sent?.0, [0x55, 0x30, 0xA5, 0x0B, 0x2E, 1, 1, 1] + Array(repeating: 0, count: 56))
        XCTAssertEqual(channel.sent?.1, 0)
    }

    func testG7RejectsTruncatedUnrelatedAndOutOfRangeReports() throws {
        let header: [UInt8] = [0xAA, 0x30, 0xA5, 0x0B, 0x0A, 1, 1, 1]
        for bytes in [[], header, header + [101, 0], [0] + Array(header.dropFirst()) + [50, 0]] {
            XCTAssertThrowsError(try G7MouseAdapter.decodeBattery(bytes))
        }
        for value: UInt8 in [0, 20, 100] {
            let reading = try G7MouseAdapter.decodeBattery(header + [value, 0])
            XCTAssertEqual(reading.percentage, Int(value))
            XCTAssertFalse(reading.charging)
        }
    }

    func testTimeoutIsOfflineAndUnsupportedIsOmitted() throws {
        let descriptor = G7MouseAdapter.descriptor
        let offline = try XCTUnwrap(MouseHardwareService.snapshot(id: "g7-42", descriptor: descriptor) {
            try G7MouseAdapter(channel: FixtureMouseTransport(reports: [])).readBattery()
        })
        XCTAssertFalse(offline.online)
        XCTAssertNil(offline.battery)
        XCTAssertEqual(offline.id, "g7-42")
        XCTAssertEqual(offline.connectionLabel, "2.4 GHz")
        XCTAssertNil(MouseHardwareService.snapshot(id: "g7-42", descriptor: descriptor) { throw MouseHardwareError.unsupported })
    }

    func testServiceRejectsInvalidBatteryAndAllowsUnknownBattery() throws {
        for value: Int? in [-1, 101, nil, 0, 100] {
            let snapshot = try XCTUnwrap(MouseHardwareService.snapshot(id: "test", descriptor: G7MouseAdapter.descriptor) {
                MouseBatteryReading(name: "Mouse", percentage: value, charging: false)
            })
            XCTAssertEqual(snapshot.online, value == nil || (0...100).contains(value!))
            XCTAssertEqual(snapshot.battery, snapshot.online ? value : nil)
        }
    }

    func testExampleCompilesAndUsesOnlyFixtureTransport() throws {
        let adapter = ExampleMouseAdapter(channel: FixtureMouseTransport(reports: [[0xBA, 67, 0]]))
        XCTAssertEqual(try adapter.readBattery().percentage, 67)
        for bytes: [UInt8] in [[], [0xBA, 255, 0], [0xBA, 50, 2], [0, 50, 0]] {
            XCTAssertThrowsError(try ExampleMouseAdapter.decode(bytes))
        }
        XCTAssertThrowsError(try ExampleMouseAdapter(channel: FixtureMouseTransport(reports: [])).readBattery())
    }
}

private final class FixtureMouseTransport: MouseReportTransport {
    let reports: [[UInt8]]
    var sent: ([UInt8], UInt32)?
    init(reports: [[UInt8]]) { self.reports = reports }

    func exchange(_ packet: [UInt8], reportID: UInt32, matching: @escaping ([UInt8]) -> Bool) throws -> [UInt8] {
        sent = (packet, reportID)
        guard let report = reports.first(where: matching) else { throw MouseHardwareError.timedOut }
        return report
    }
}
