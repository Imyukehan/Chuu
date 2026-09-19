import XCTest
@testable import Chuu

final class ChuuBrandingTests: XCTestCase {
    func testCompiledDisplayStringsDoNotUseLegacyBrand() throws {
        let resources = try XCTUnwrap(Bundle.main.resourceURL)
        let files = try XCTUnwrap(FileManager.default.enumerator(at: resources, includingPropertiesForKeys: nil))
        var catalogCount = 0
        for case let url as URL in files where url.pathExtension == "strings" {
            guard ["Main", "Localizable", "Chuu"].contains(url.deletingPathExtension().lastPathComponent) else { continue }
            let values = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil) as? [String: String])
            catalogCount += 1
            for (key, value) in values {
                XCTAssertNil(value.range(of: "(?i)(?<![a-z])mos(?![a-z])", options: .regularExpression),
                             "Legacy display branding in \(url.lastPathComponent), \(key): \(value)")
            }
        }
        XCTAssertGreaterThanOrEqual(catalogCount, 32)
    }

    func testHideStatusIconHelpUsesChuu() throws {
        let path = try XCTUnwrap(Bundle.main.path(forResource: "zh-Hans", ofType: "lproj"))
        let chinese = try XCTUnwrap(Bundle(path: path))
        let help = chinese.localizedString(forKey: "cIk-j1-vYt.title", value: nil, table: "Main")
        XCTAssertTrue(help.contains("Chuu"))
    }

    func testExistingShortcutIdentifiersDisplayChuu() {
        for identifier in ["mosScrollDash", "mosScrollToggle", "mosScrollBlock"] {
            XCTAssertEqual(BrandTag.tagForAction(identifier)?.name, "Chuu")
        }
    }
}
