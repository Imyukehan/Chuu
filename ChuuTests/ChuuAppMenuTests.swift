import AppKit
import XCTest
@testable import Chuu

@MainActor
final class ChuuAppMenuTests: XCTestCase {
    func testStandardMenuStructureDoesNotDuplicateOnRebuild() {
        let owner = ChuuAppMenu()
        for _ in 0..<2 {
            let menu = owner.makeMenu()
            XCTAssertEqual(menu.items.map(\.title), ["Chuu", tr("File"), tr("Edit"), tr("Window"), tr("Help")])
            XCTAssertTrue(menu.items.allSatisfy { $0.submenu != nil })
        }
    }

    func testAppCommandsHaveExplicitTargetsAndSettingsShortcut() throws {
        let owner = ChuuAppMenu()
        let app = try XCTUnwrap(owner.makeMenu().items.first?.submenu)
        for (key, action) in [("About Chuu", #selector(ChuuAppMenu.showAbout)),
                              ("Check for Updates…", #selector(ChuuAppMenu.checkForUpdates)),
                              ("Settings…", #selector(ChuuAppMenu.showSettings))] {
            let item = try XCTUnwrap(app.item(withTitle: tr(key)))
            XCTAssertEqual(item.action, action)
            XCTAssertTrue(item.target === owner)
        }
        let settings = try XCTUnwrap(app.item(withTitle: tr("Settings…")))
        XCTAssertEqual(settings.keyEquivalent, ",")
        XCTAssertEqual(settings.keyEquivalentModifierMask, .command)
    }

    func testStandardShortcutsUseResponderChain() throws {
        let menu = ChuuAppMenu().makeMenu()
        for (section, title, shortcut, selector) in [
            (0, "Quit Chuu", "q", #selector(NSApplication.terminate(_:))),
            (1, "Close Window", "w", #selector(NSWindow.performClose(_:))),
            (2, "Copy", "c", #selector(NSText.copy(_:))),
            (2, "Paste", "v", #selector(NSText.paste(_:))),
            (3, "Minimize", "m", #selector(NSWindow.performMiniaturize(_:)))
        ] {
            let item = try XCTUnwrap(menu.items[section].submenu?.item(withTitle: tr(title)))
            XCTAssertEqual(item.action, selector)
            XCTAssertNil(item.target)
            XCTAssertEqual(item.keyEquivalent, shortcut)
            XCTAssertEqual(item.keyEquivalentModifierMask, .command)
        }
    }

    func testUpdateFeedRequiresHTTPSAndValidPublicKey() {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        XCTAssertTrue(UpdateManager.hasConfiguration(["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": key]))
        XCTAssertFalse(UpdateManager.hasConfiguration([:]))
        XCTAssertFalse(UpdateManager.hasConfiguration(["SUFeedURL": "https://example.com/appcast.xml"]))
        for feed in ["http://example.com/appcast.xml", "file:///tmp/appcast.xml", "appcast.xml"] {
            XCTAssertFalse(UpdateManager.hasConfiguration(["SUFeedURL": feed, "SUPublicEDKey": key]))
        }
        for invalidKey in ["", "invalid", Data(repeating: 1, count: 31).base64EncodedString()] {
            XCTAssertFalse(UpdateManager.hasConfiguration(["SUFeedURL": "https://example.com/appcast.xml", "SUPublicEDKey": invalidKey]))
        }
    }

    func testUpstreamFeedCannotUpdateChuu() {
        let key = Data(repeating: 1, count: 32).base64EncodedString()
        for feed in ["https://mos.caldis.me/appcast.xml", "https://updates.caldis.me/appcast.xml"] {
            XCTAssertFalse(UpdateManager.hasConfiguration(["SUFeedURL": feed, "SUPublicEDKey": key]))
        }
    }

    func testRepositoryDestinationsBelongToChuu() {
        XCTAssertEqual(ChuuAppMenu.repositoryURL.absoluteString, "https://github.com/Imyukehan/Chuu")
        XCTAssertEqual(ChuuAppMenu.releasesURL.absoluteString, "https://github.com/Imyukehan/Chuu/releases")
    }

    func testMenuCommandsAreLocalized() throws {
        for (locale, expected) in [("en", "Check for Updates…"), ("zh-Hans", "检查更新…")] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: locale, ofType: "lproj"))
            let bundle = try XCTUnwrap(Bundle(path: path))
            XCTAssertEqual(bundle.localizedString(forKey: "Check for Updates…", value: nil, table: "Chuu"), expected)
        }
    }

    private func tr(_ key: String) -> String { NSLocalizedString(key, tableName: "Chuu", comment: "") }
}
