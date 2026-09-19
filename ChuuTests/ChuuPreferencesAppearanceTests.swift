import AppKit
import XCTest
@testable import Chuu

@MainActor
final class ChuuPreferencesAppearanceTests: XCTestCase {
    func testEmbeddedPanesDoNotAddTheirOwnWindowMaterial() {
        // The SwiftUI host owns the window material, including inactive appearance.
        for identifier in ["general", "scrolling", "application", "buttons"] {
            let controller: NSViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: identifier)
            for appearance in [NSAppearance.Name.aqua, .darkAqua] {
                controller.view.appearance = NSAppearance(named: appearance)
                let materials = descendants(of: controller.view).compactMap { $0 as? NSVisualEffectView }
                XCTAssertTrue(materials.isEmpty, "\(identifier) adds a separate background in \(appearance)")
                XCTAssertFalse(controller.view.isOpaque, identifier)
            }
        }
    }

    func testApplicationTableAndHeaderRemainTransparent() throws {
        let controller: NSViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: "application")
        let applications = try XCTUnwrap(controller as? PreferencesApplicationViewController)
        _ = applications.view
        XCTAssertFalse(applications.tableHead is NSVisualEffectView)
        XCTAssertNil(applications.tableHead.appearance)
        let scroll = try XCTUnwrap(applications.tableView.enclosingScrollView)
        XCTAssertFalse(scroll.drawsBackground)
        XCTAssertFalse(scroll.contentView.drawsBackground)
        XCTAssertEqual(applications.tableView.backgroundColor.alphaComponent, 0)
        XCTAssertNotNil(applications.allowlistModeCheckBox.action)
        XCTAssertNotNil(applications.addButton.action)
        XCTAssertNotNil(applications.delButton.action)
    }

    private func descendants(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { descendants(of: $0) }
    }
}
