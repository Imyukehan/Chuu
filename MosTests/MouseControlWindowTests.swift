import AppKit
import XCTest
@testable import Mos_Debug

@available(macOS 14.0, *)
final class MouseControlWindowTests: XCTestCase {
    @MainActor
    func testMainWindowHasFixedLandscapeSize() throws {
        let window = try XCTUnwrap(MouseControlWindow.shared.window)
        let expected = NSSize(width: 1060, height: 700)
        XCTAssertEqual(window.contentMinSize, expected)
        XCTAssertEqual(window.contentMaxSize, expected)
        XCTAssertEqual(window.contentRect(forFrameRect: window.frame).size, expected)
        XCTAssertFalse(window.styleMask.contains(.resizable))
        XCTAssertFalse(window.isRestorable)
        XCTAssertTrue(window.collectionBehavior.contains(.fullScreenNone))
        XCTAssertFalse(try XCTUnwrap(window.standardWindowButton(.zoomButton)).isEnabled)
    }

    @MainActor
    func testClosingMainWindowHidesDockEvenWithTransientPanel() {
        let previousPolicy = NSApp.activationPolicy()
        let previousFlag = Utils.isDockIconVisible
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 40, height: 40),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        defer {
            panel.close()
            NSApp.setActivationPolicy(previousPolicy)
            Utils.isDockIconVisible = previousFlag
        }
        panel.orderFront(nil)
        XCTAssertTrue(panel.isVisible)
        NSApp.setActivationPolicy(.regular)
        Utils.isDockIconVisible = true
        MouseControlWindow.shared.windowWillClose(Notification(name: NSWindow.willCloseNotification))
        XCTAssertEqual(NSApp.activationPolicy(), .accessory)
        XCTAssertFalse(Utils.isDockIconVisible)
        Utils.showDockIcon()
        XCTAssertEqual(NSApp.activationPolicy(), .regular)
        XCTAssertTrue(Utils.isDockIconVisible)
    }

    @MainActor
    func testClosingLastWindowKeepsBackgroundAppRunning() {
        XCTAssertFalse(AppDelegate().applicationShouldTerminateAfterLastWindowClosed(NSApp))
    }
}
