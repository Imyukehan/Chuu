//
//  UpdateManager.swift
//  Mos
//  Updates management via Sparkle
//

import Cocoa
import Sparkle

final class UpdateManager: NSObject {

    static let shared = UpdateManager()

    static func hasConfiguration(_ info: [String: Any]) -> Bool {
        guard let feed = info["SUFeedURL"] as? String, let url = URL(string: feed),
              url.scheme == "https", let host = url.host, !host.isEmpty,
              host != "mos.caldis.me", !host.hasSuffix(".caldis.me"),
              let key = info["SUPublicEDKey"] as? String, Data(base64Encoded: key)?.count == 32 else { return false }
        return true
    }

    private var isConfigured: Bool { Self.hasConfiguration(Bundle.main.infoDictionary ?? [:]) }
    private var configurationNotice: NSAlert?

    private lazy var updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    private override init() {
        super.init()
        NSLog("Module initialized: UpdateManager")
    }
}

extension UpdateManager {

    func scheduleCheckOnAppStartIfNeeded() {
        guard isConfigured else { return }
        guard Options.shared.update.checkOnAppStart else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        guard isConfigured else { showConfigurationNotice(); return }
        updaterController.checkForUpdates(nil)
    }

    func checkForUpdatesInBackground() {
        guard isConfigured else { return }
        updaterController.updater.checkForUpdatesInBackground()
    }

    private func showConfigurationNotice() {
        ChuuWindow.shared.present()
        guard configurationNotice == nil, let window = ChuuWindow.shared.window,
              window.attachedSheet == nil else { return }
        let alert = NSAlert()
        alert.messageText = NSLocalizedString("Updates Not Configured", tableName: "Chuu", comment: "Development update state")
        alert.informativeText = NSLocalizedString("This development build has no update feed configured. You can view published versions on GitHub Releases.",
                                                 tableName: "Chuu", comment: "Development update state")
        alert.addButton(withTitle: NSLocalizedString("Not Now", tableName: "Chuu", comment: "Dismiss update notice"))
        alert.addButton(withTitle: NSLocalizedString("View Releases", tableName: "Chuu", comment: "Open releases"))
        configurationNotice = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            self?.configurationNotice = nil
            if response == .alertSecondButtonReturn { NSWorkspace.shared.open(ChuuAppMenu.releasesURL) }
        }
    }
}

extension UpdateManager: SPUUpdaterDelegate {

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Options.shared.update.includingBetaVersion ? ["beta"] : []
    }
}
