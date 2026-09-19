import XCTest
@testable import Chuu

@available(macOS 14.0, *)
final class ChuuNavigationTests: XCTestCase {
    func testTabsMatchStoryboardRoutesInDisplayOrder() {
        XCTAssertEqual(ChuuNavigation.Page.allCases.map(\.rawValue),
                       ["device", "scrolling", "application", "general"])
    }

    func testSelectionVisitsEveryPage() {
        let navigation = ChuuNavigation()
        XCTAssertEqual(navigation.page, .device)
        for (index, page) in ChuuNavigation.Page.allCases.enumerated() {
            navigation.select(index: index)
            XCTAssertEqual(navigation.page, page)
        }
    }

    func testInvalidSelectionKeepsCurrentPage() {
        let navigation = ChuuNavigation()
        navigation.select(index: 3)
        navigation.select(index: -1)
        XCTAssertEqual(navigation.page, .general)
        navigation.select(index: 4)
        XCTAssertEqual(navigation.page, .general)
    }
}
