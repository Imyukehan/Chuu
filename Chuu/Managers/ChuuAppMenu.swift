import AppKit

final class ChuuAppMenu: NSObject {
    static let shared = ChuuAppMenu()
    static let repositoryURL = URL(string: "https://github.com/Imyukehan/Chuu")!
    static let releasesURL = repositoryURL.appendingPathComponent("releases")
    private var servicesMenu: NSMenu?
    private var windowsMenu: NSMenu?
    private var helpMenu: NSMenu?

    func install() {
        NSApp.mainMenu = makeMenu()
        NSApp.servicesMenu = servicesMenu
        NSApp.windowsMenu = windowsMenu
        NSApp.helpMenu = helpMenu
    }

    func makeMenu() -> NSMenu {
        let main = NSMenu(title: "Main Menu")
        func submenu(_ title: String) -> NSMenu {
            let item = main.addItem(withTitle: title, action: nil, keyEquivalent: "")
            let menu = NSMenu(title: title)
            item.submenu = menu
            return menu
        }
        let app = submenu("Chuu")
        add("About Chuu", to: app, action: #selector(showAbout), target: self)
        add("Check for Updates…", to: app, action: #selector(checkForUpdates), target: self)
        app.addItem(.separator())
        add("Settings…", to: app, action: #selector(showSettings), key: ",", target: self)
        app.addItem(.separator())
        let services = NSMenu(title: tr("Services"))
        add("Services", to: app, action: nil).submenu = services
        servicesMenu = services
        app.addItem(.separator())
        add("Hide Chuu", to: app, action: #selector(NSApplication.hide(_:)), key: "h")
        add("Hide Others", to: app, action: #selector(NSApplication.hideOtherApplications(_:)), key: "h")
            .keyEquivalentModifierMask = [.command, .option]
        add("Show All", to: app, action: #selector(NSApplication.unhideAllApplications(_:)))
        app.addItem(.separator())
        add("Quit Chuu", to: app, action: #selector(NSApplication.terminate(_:)), key: "q")

        let file = submenu(tr("File"))
        add("Open Chuu", to: file, action: #selector(showMainWindow), key: "0", target: self)
        add("Close Window", to: file, action: #selector(NSWindow.performClose(_:)), key: "w")

        let edit = submenu(tr("Edit"))
        add("Undo", to: edit, action: Selector(("undo:")), key: "z")
        add("Redo", to: edit, action: Selector(("redo:")), key: "z").keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        add("Cut", to: edit, action: #selector(NSText.cut(_:)), key: "x")
        add("Copy", to: edit, action: #selector(NSText.copy(_:)), key: "c")
        add("Paste", to: edit, action: #selector(NSText.paste(_:)), key: "v")
        add("Select All", to: edit, action: #selector(NSText.selectAll(_:)), key: "a")

        let window = submenu(tr("Window"))
        add("Minimize", to: window, action: #selector(NSWindow.performMiniaturize(_:)), key: "m")
        add("Bring All to Front", to: window, action: #selector(NSApplication.arrangeInFront(_:)))
        windowsMenu = window

        let help = submenu(tr("Help"))
        add("Chuu on GitHub", to: help, action: #selector(openRepository), target: self)
        add("Report an Issue", to: help, action: #selector(reportIssue), target: self)
        helpMenu = help
        return main
    }

    @discardableResult
    private func add(_ key: String, to menu: NSMenu, action: Selector?, key equivalent: String = "",
                     target: AnyObject? = nil) -> NSMenuItem {
        let item = menu.addItem(withTitle: tr(key), action: action, keyEquivalent: equivalent)
        item.target = target
        return item
    }

    @objc func showAbout() {
        Utils.showDockIcon()
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "Chuu",
            .credits: NSAttributedString(string: "")
        ])
    }

    @objc func checkForUpdates() { UpdateManager.shared.checkForUpdates() }
    @objc func showSettings() { ChuuWindow.shared.present(page: .general) }
    @objc func showMainWindow() { ChuuWindow.shared.present() }
    @objc func openRepository() { NSWorkspace.shared.open(Self.repositoryURL) }
    @objc func reportIssue() { NSWorkspace.shared.open(Self.repositoryURL.appendingPathComponent("issues")) }

    private func tr(_ key: String) -> String { NSLocalizedString(key, tableName: "Chuu", comment: "Application menu") }
}
