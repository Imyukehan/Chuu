import XCTest
@testable import Mos_Debug

@available(macOS 14.0, *)
final class MouseControlNavigationTests: XCTestCase {
    func testTabsMatchStoryboardRoutesInDisplayOrder() {
        XCTAssertEqual(MouseControlNavigation.Page.allCases.map(\.rawValue),
                       ["device", "scrolling", "buttons", "application", "general"])
    }

    func testSelectionVisitsEveryPage() {
        let navigation = MouseControlNavigation()
        XCTAssertEqual(navigation.page, .device)
        for (index, page) in MouseControlNavigation.Page.allCases.enumerated() {
            navigation.select(index: index)
            XCTAssertEqual(navigation.page, page)
        }
    }

    func testInvalidSelectionKeepsCurrentPage() {
        let navigation = MouseControlNavigation()
        navigation.select(index: 4)
        navigation.select(index: -1)
        XCTAssertEqual(navigation.page, .general)
        navigation.select(index: 5)
        XCTAssertEqual(navigation.page, .general)
    }
}
