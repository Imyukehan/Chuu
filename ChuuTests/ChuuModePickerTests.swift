import AppKit
import SwiftUI
import XCTest
@testable import Chuu

@MainActor
final class ChuuModePickerTests: XCTestCase {
    func testNativeTabsKeepSingleSelectionAndEqualSegments() {
        let control = ChuuModePicker.makeControl(titles: ["Top", "Side"])
        XCTAssertEqual(control.segmentCount, 2)
        XCTAssertEqual(control.trackingMode, .selectOne)
        XCTAssertEqual(control.segmentDistribution, .fillEqually)
        if #available(macOS 26.0, *) { XCTAssertEqual(control.borderShape, .capsule) }
        if #available(macOS 27.0, *) { XCTAssertEqual(control.role, .tabs) }
    }

    func testSelectionWritesThroughBindingAndIgnoresEmptySelection() {
        var selected = false
        let coordinator = ChuuModePicker.Coordinator(selection: Binding(get: { selected }, set: { selected = $0 }))
        let control = ChuuModePicker.makeControl(titles: ["Top", "Side"])
        control.selectedSegment = 1
        coordinator.select(control)
        XCTAssertTrue(selected)
        control.selectedSegment = -1
        coordinator.select(control)
        XCTAssertTrue(selected)
        control.selectedSegment = 0
        coordinator.select(control)
        XCTAssertFalse(selected)
    }

    func testShortcutPaneDoesNotAddAnInactiveMaterialBackground() throws {
        let controller: NSViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: "buttons")
        let buttons = try XCTUnwrap(controller as? PreferencesButtonsViewController)
        _ = buttons.view
        XCTAssertFalse(buttons.view is NSVisualEffectView)
        XCTAssertFalse(buttons.tableHead is NSVisualEffectView)
        XCTAssertFalse(try XCTUnwrap(buttons.tableView.enclosingScrollView).drawsBackground)
        XCTAssertEqual(buttons.tableView.backgroundColor.alphaComponent, 0)
    }

    func testShortcutTitleIsConciseInBothLanguages() throws {
        for (locale, expected) in [("en", "Shortcuts"), ("zh-Hans", "快捷操作")] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: locale, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(bundle.localizedString(forKey: "Shortcuts (all mice)", value: nil, table: "Chuu"), expected)
        }
    }
}
