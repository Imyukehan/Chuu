//
//  UpdateManager.swift
//  Mos
//  Updates management via Sparkle
//

import Cocoa
import Sparkle

final class UpdateManager: NSObject {

    static let shared = UpdateManager()

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
        guard Bundle.main.bundleIdentifier?.hasPrefix("com.caldis.Mos") == true else { return }
        guard Options.shared.update.checkOnAppStart else { return }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.checkForUpdatesInBackground()
        }
    }

    func checkForUpdates() {
        guard Bundle.main.bundleIdentifier?.hasPrefix("com.caldis.Mos") == true else { return }
        updaterController.checkForUpdates(nil)
    }

    func checkForUpdatesInBackground() {
        guard Bundle.main.bundleIdentifier?.hasPrefix("com.caldis.Mos") == true else { return }
        updaterController.updater.checkForUpdatesInBackground()
    }
}

extension UpdateManager: SPUUpdaterDelegate {

    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        Options.shared.update.includingBetaVersion ? ["beta"] : []
    }
}
