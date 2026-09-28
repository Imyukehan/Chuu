import AppKit
import IOKit
import UserNotifications
import XCTest
@testable import Chuu

final class ChuuPermissionTests: XCTestCase {
    func testBothInputPermissionsAreRequired() {
        for accessibility in [false, true] {
            for input in [false, true] {
                let state = ChuuPermissionState(accessibility: accessibility, inputMonitoring: input)
                XCTAssertEqual(state.requiredGranted, accessibility && input)
            }
        }
    }

    func testNotificationsNeverBlockCoreFeatures() {
        for status: UNAuthorizationStatus in [.notDetermined, .denied, .authorized, .provisional] {
            let state = ChuuPermissionState(accessibility: true, inputMonitoring: true, notifications: status)
            XCTAssertTrue(state.requiredGranted)
            XCTAssertFalse(state.needsSetup(completed: true))
            XCTAssertEqual(state.allDecided, status != .notDetermined)
        }
    }

    func testFirstLaunchShowsSetupEvenWhenPreviouslyAuthorized() {
        let state = ChuuPermissionState(accessibility: true, inputMonitoring: true, notifications: .authorized)
        XCTAssertTrue(state.needsSetup(completed: false))
        XCTAssertFalse(state.needsSetup(completed: true))
    }

    func testRevokedPermissionReopensSetupAfterCompletion() {
        XCTAssertTrue(ChuuPermissionState(accessibility: false, inputMonitoring: true).needsSetup(completed: true))
        XCTAssertTrue(ChuuPermissionState(accessibility: true, inputMonitoring: false).needsSetup(completed: true))
    }

    func testAccessDeniedHasActionableMessage() {
        let message = MouseHardwareError.io(kIOReturnNotPermitted).localizedDescription
        XCTAssertFalse(message.contains("0xE00002E2"))
        XCTAssertTrue(MouseHardwareError.io(kIOReturnNotPermitted).isAccessDenied)
        XCTAssertFalse(MouseHardwareError.io(kIOReturnTimeout).isAccessDenied)
        XCTAssertFalse(MouseHardwareError.unavailable.isAccessDenied)
        XCTAssertEqual(MouseHardwareError.io(kIOReturnTimeout).localizedDescription, "HID: 0xE00002D6")
    }

    func testPermissionRecoveryHasEnglishAndChineseInstructions() throws {
        let bundle = Bundle(for: AppDelegate.self)
        for language in ["en", "zh-Hans"] {
            let path = try XCTUnwrap(bundle.path(forResource: language, ofType: "lproj"))
            let localized = try XCTUnwrap(Bundle(path: path))
            let text = localized.localizedString(forKey: ChuuPermissions.recoveryInstructions,
                                                 value: "MISSING", table: "Chuu")
            XCTAssertNotEqual(text, "MISSING")
            XCTAssertTrue(text.contains("Chuu"))
        }
    }

    @MainActor
    func testInheritedStoryboardLoadsMultiPermissionWindow() throws {
        let controller: NSWindowController = Utils.instantiateControllerFromStoryboard(
            withIdentifier: WINDOW_IDENTIFIER.introductionWindowController)
        let window = try XCTUnwrap(controller.window)
        let content = try XCTUnwrap(controller.contentViewController as? IntroductionViewController)
        _ = content.view
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, NSSize(width: 460, height: 440))
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertEqual(content.view.subviews.count, 1)
    }

    @MainActor
    func testClosingPermissionsKeepsDockForVisibleMainWindow() throws {
        let policy = NSApp.activationPolicy()
        let flag = Utils.isDockIconVisible
        let main = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
                            styleMask: [.titled], backing: .buffered, defer: false)
        main.isReleasedWhenClosed = false
        defer {
            main.close()
            NSApp.setActivationPolicy(policy)
            Utils.isDockIconVisible = flag
        }
        main.orderFront(nil)
        Utils.showDockIcon()
        let controller: IntroductionWindowController = Utils.instantiateControllerFromStoryboard(
            withIdentifier: WINDOW_IDENTIFIER.introductionWindowController)
        controller.windowWillClose(Notification(name: NSWindow.willCloseNotification, object: controller.window))
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        XCTAssertTrue(Utils.isDockIconVisible)
    }
}
