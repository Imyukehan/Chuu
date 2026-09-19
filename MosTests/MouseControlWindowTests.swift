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
}
