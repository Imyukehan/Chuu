import XCTest
@testable import Mos_Debug

final class MouseAlertPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private func device(_ id: String = "mouse", battery: Int? = 70, online: Bool = true, charging: Bool = false) -> MouseSnapshot {
        MouseSnapshot(id: id, model: "generic", name: "Mouse", battery: battery,
                      charging: charging, online: online, updatedAt: now)
    }

    func testInitialScanDoesNotAnnounceExistingDevices() {
        var policy = MouseAlertPolicy()
        XCTAssertEqual(policy.consume([device()], at: now, lowBatteryEnabled: true), [])
    }

    func testNewConnectionIsAnnouncedOnce() {
        var policy = MouseAlertPolicy()
        _ = policy.consume([], at: now, lowBatteryEnabled: true)
        XCTAssertEqual(policy.consume([device()], at: now, lowBatteryEnabled: true), [.connected("mouse")])
        XCTAssertEqual(policy.consume([device()], at: now, lowBatteryEnabled: true), [])
    }

    func testSingleMissedResponseDoesNotCauseReconnect() {
        var policy = MouseAlertPolicy()
        _ = policy.consume([device()], at: now, lowBatteryEnabled: true)
        _ = policy.consume([device(online: false)], at: now, lowBatteryEnabled: true)
        XCTAssertEqual(policy.consume([device()], at: now, lowBatteryEnabled: true), [])
    }

    func testReconnectIsDebouncedAndRateLimited() {
        var policy = MouseAlertPolicy()
        _ = policy.consume([device()], at: now, lowBatteryEnabled: true)
        for _ in 0..<2 { _ = policy.consume([], at: now, lowBatteryEnabled: true) }
        XCTAssertEqual(policy.consume([device()], at: now, lowBatteryEnabled: true), [.connected("mouse")])
        for _ in 0..<2 { _ = policy.consume([], at: now, lowBatteryEnabled: true) }
        XCTAssertEqual(policy.consume([device()], at: now.addingTimeInterval(90), lowBatteryEnabled: true), [])
    }

    func testWakeRebaselineDoesNotAnnounce() {
        var policy = MouseAlertPolicy()
        _ = policy.consume([], at: now, lowBatteryEnabled: true)
        policy.rebaseline()
        XCTAssertEqual(policy.consume([device()], at: now, lowBatteryEnabled: true), [])
        policy.rebaseline()
        _ = policy.consume([device(online: false)], at: now, lowBatteryEnabled: false)
        XCTAssertEqual(policy.consume([device()], at: now, lowBatteryEnabled: false), [])
    }

    func testLowBatteryWarnsOnceUntilRecovery() {
        var policy = MouseAlertPolicy()
        XCTAssertEqual(policy.consume([device(battery: 20)], at: now, lowBatteryEnabled: true), [.lowBattery("mouse")])
        policy.didNotifyLowBattery("mouse")
        XCTAssertEqual(policy.consume([device(battery: 10)], at: now, lowBatteryEnabled: true), [])
        _ = policy.consume([device(battery: 24)], at: now, lowBatteryEnabled: true)
        XCTAssertEqual(policy.consume([device(battery: 20)], at: now, lowBatteryEnabled: true), [])
        _ = policy.consume([device(battery: 25)], at: now, lowBatteryEnabled: true)
        XCTAssertEqual(policy.consume([device(battery: 20)], at: now, lowBatteryEnabled: true), [.lowBattery("mouse")])
    }

    func testChargingUnknownOfflineAndDisabledReadingsDoNotWarn() {
        var policy = MouseAlertPolicy()
        XCTAssertEqual(policy.consume([device(battery: 10, charging: true)], at: now, lowBatteryEnabled: true), [])
        XCTAssertEqual(policy.consume([device(battery: nil)], at: now, lowBatteryEnabled: true), [])
        XCTAssertEqual(policy.consume([device(battery: 10, online: false)], at: now, lowBatteryEnabled: true), [])
        XCTAssertEqual(policy.consume([device(battery: 10)], at: now, lowBatteryEnabled: false), [])
        XCTAssertTrue(policy.warnedDevices.isEmpty)
    }

    func testSleepingRadioDoesNotBecomeANewConnectionEvenAfterManyPolls() {
        var policy = MouseAlertPolicy()
        _ = policy.consume([device()], at: now, lowBatteryEnabled: false)
        for _ in 0..<20 { _ = policy.consume([device(online: false)], at: now, lowBatteryEnabled: false) }
        XCTAssertEqual(policy.consume([device()], at: now.addingTimeInterval(600), lowBatteryEnabled: false), [])
    }

    func testInitiallySleepingReceiverAnnouncesFirstSuccessfulRead() {
        var policy = MouseAlertPolicy()
        _ = policy.consume([device(online: false)], at: now, lowBatteryEnabled: false)
        XCTAssertEqual(policy.consume([device()], at: now, lowBatteryEnabled: false), [.connected("mouse")])
    }

    func testFastPhysicalReconnectDoesNotRequireAMissedPoll() {
        var policy = MouseAlertPolicy()
        _ = policy.consume([device()], at: now, lowBatteryEnabled: false)
        policy.deviceRemoved("mouse")
        XCTAssertEqual(policy.consume([device()], at: now, lowBatteryEnabled: false), [.connected("mouse")])
    }

    func testFailedOrDeniedNotificationCanRetry() {
        var policy = MouseAlertPolicy()
        _ = policy.consume([device(battery: 10)], at: now, lowBatteryEnabled: true)
        XCTAssertTrue(policy.warnedDevices.isEmpty)
        XCTAssertEqual(policy.consume([device(battery: 10)], at: now, lowBatteryEnabled: true), [.lowBattery("mouse")])
        policy.didNotifyLowBattery("mouse")
        XCTAssertEqual(policy.consume([device(battery: 10)], at: now, lowBatteryEnabled: true), [])
    }

    func testConnectionPanelCannotStealKeyboardFocus() {
        let panel = MouseConnectionPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                                         backing: .buffered, defer: false)
        XCTAssertFalse(panel.canBecomeKey)
        XCTAssertFalse(panel.canBecomeMain)
        XCTAssertTrue(panel.styleMask.contains(.nonactivatingPanel))
    }

    func testGenericDiscoveryExcludesNonMouseInterfaces() {
        XCTAssertTrue(MouseDeviceDiscovery.isGenericMouse(name: "USB Mouse", builtIn: false, transport: "USB"))
        XCTAssertTrue(MouseDeviceDiscovery.isGenericMouse(name: "Magic Mouse", builtIn: false, transport: "Bluetooth"))
        for name in ["Apple Internal Keyboard / Trackpad", "K3 Keyboard", "USB Receiver", "Virtual Mouse"] {
            XCTAssertFalse(MouseDeviceDiscovery.isGenericMouse(name: name, builtIn: false, transport: "USB"))
        }
        XCTAssertFalse(MouseDeviceDiscovery.isGenericMouse(name: "Mouse", builtIn: true, transport: "USB"))
        XCTAssertFalse(MouseDeviceDiscovery.isGenericMouse(name: "Mouse", builtIn: false, transport: "Virtual"))
    }

    func testStaleBatteryDoesNotWarn() {
        var policy = MouseAlertPolicy()
        XCTAssertEqual(policy.consume([device(battery: 10)], at: now.addingTimeInterval(1801), lowBatteryEnabled: true), [])
    }

    func testPersistedWarningsPreventRestartSpamAndDevicesAreIndependent() {
        var policy = MouseAlertPolicy(warnedDevices: ["mouse"])
        XCTAssertEqual(policy.consume([device(battery: 10), device("other", battery: 15)], at: now, lowBatteryEnabled: true), [.lowBattery("other")])
    }

    func testOldSnapshotDecodesWithoutTransportAndUnknownModelsUseGenericArtwork() throws {
        let encoded = try JSONEncoder().encode(device())
        let decoded = try JSONDecoder().decode(MouseSnapshot.self, from: encoded)
        XCTAssertNil(decoded.transport)
        XCTAssertEqual(decoded.imageName, "")
        XCTAssertEqual(decoded.connectionLabel, "USB")
    }
}
