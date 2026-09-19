import AppKit
import SwiftUI

@available(macOS 14.0, *)
final class MouseControlNavigation: ObservableObject {
    enum Page: String, CaseIterable {
        case device, scrolling, buttons, application, general

        var title: String {
            let key: String
            switch self {
            case .device: key = "Mouse"
            case .scrolling: key = "Scrolling"
            case .buttons: key = "Buttons"
            case .application: key = "Application"
            case .general: key = "General"
            }
            return NSLocalizedString(key, tableName: "MouseControl", comment: "Navigation tab")
        }
    }

    @Published private(set) var page: Page = .device

    func select(index: Int) {
        guard Page.allCases.indices.contains(index) else { return }
        page = Page.allCases[index]
    }
}

@available(macOS 14.0, *)
final class MouseControlWindow: NSWindowController, NSWindowDelegate, NSToolbarDelegate {
    static let shared = MouseControlWindow()
    private static let navigationID = NSToolbarItem.Identifier("Chuu.Navigation")
    private let navigation: MouseControlNavigation

    private init() {
        let navigation = MouseControlNavigation()
        self.navigation = navigation
        let contentSize = NSSize(width: 1060, height: 700)
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: contentSize),
                              styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                              backing: .buffered, defer: false)
        window.title = "Chuu"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.collectionBehavior = [.fullScreenNone, .fullScreenDisallowsTiling]
        let hostingController = NSHostingController(rootView: MouseControlView(model: .shared, navigation: navigation))
        // Switching to a compact preferences pane must not shrink the window.
        hostingController.sizingOptions = []
        window.contentViewController = hostingController
        super.init(window: window)
        window.delegate = self
        let toolbar = NSToolbar(identifier: "Chuu.MainToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        toolbar.showsBaselineSeparator = false
        toolbar.centeredItemIdentifiers = [Self.navigationID]
        window.toolbar = toolbar
        window.toolbarStyle = .unified
        window.setContentSize(contentSize)
        window.contentMinSize = contentSize
        window.contentMaxSize = contentSize
        window.standardWindowButton(.zoomButton)?.isEnabled = false
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.navigationID]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Self.navigationID]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard itemIdentifier == Self.navigationID else { return nil }
        let item = NSToolbarItemGroup(itemIdentifier: itemIdentifier,
                                      titles: MouseControlNavigation.Page.allCases.map(\.title),
                                      selectionMode: .selectOne, labels: nil,
                                      target: self, action: #selector(selectPage(_:)))
        item.controlRepresentation = .expanded
        item.selectedIndex = MouseControlNavigation.Page.allCases.firstIndex(of: navigation.page) ?? 0
        if #available(macOS 27.0, *) { item.role = .tabs }
        return item
    }

    @objc private func selectPage(_ sender: NSToolbarItemGroup) {
        navigation.select(index: sender.selectedIndex)
    }

    func present() {
        MouseControlModel.shared.start()
        Utils.showDockIcon()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // Status-item and transient panels are not reasons to keep a Dock icon.
        NSApp.setActivationPolicy(.accessory)
        Utils.isDockIconVisible = false
    }
}

@available(macOS 14.0, *)
struct MouseWindowMaterial: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .underWindowBackground
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }
    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

@available(macOS 14.0, *)
struct MosPreferencesPane: NSViewControllerRepresentable {
    let identifier: String
    func makeNSViewController(context: Context) -> NSViewController {
        let controller: NSViewController = Utils.instantiateControllerFromStoryboard(withIdentifier: identifier)
        compactHelp(in: controller)
        return controller
    }
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) { compactHelp(in: nsViewController) }

    private func compactHelp(in controller: NSViewController) {
        guard let scrolling = controller as? PreferencesScrollingViewController else { return }
        _ = scrolling.view
        let controls: [String: NSView] = [
            "dash": scrolling.dashKeyBindButton, "toggle": scrolling.toggleKeyBindButton,
            "block": scrolling.disableKeyBindButton, "step": scrolling.scrollStepSlider,
            "speed": scrolling.scrollSpeedSlider, "duration": scrolling.scrollDurationSlider
        ]
        for case let field as NSTextField in scrolling.view.subviews {
            guard let identifier = field.identifier?.rawValue,
                  identifier.hasPrefix("mouseControl.help."),
                  let key = identifier.split(separator: ".").last,
                  let control = controls[String(key)] else { continue }
            control.toolTip = field.stringValue
            field.isHidden = true
        }
    }
}
