import AppKit
import Combine
import IOKit.hid
import UserNotifications

struct ChuuPermissionState: Equatable {
    var accessibility = false
    var inputMonitoring = false
    var notifications: UNAuthorizationStatus = .notDetermined

    var requiredGranted: Bool { accessibility && inputMonitoring }
    var allDecided: Bool { requiredGranted && notifications != .notDetermined }
    func needsSetup(completed: Bool) -> Bool { !requiredGranted || !completed }
}

final class ChuuPermissions: ObservableObject {
    static let recoveryInstructions = "If Chuu is already enabled, quit Chuu, remove its old entry from Input Monitoring and Accessibility, then add the current app and enable it again. Reopen Chuu afterward."
    static let shared = ChuuPermissions()
    static let changed = Notification.Name("ChuuPermissionsChanged")
    private static let completedKey = "chuu.permissionsSetupCompleted"
    @Published private(set) var state = ChuuPermissionState()
    private var requestingNotifications = false

    static var isPreview: Bool {
        #if DEBUG
        return ProcessInfo.processInfo.arguments.contains("-ChuuPreviewPermissions")
        #else
        return false
        #endif
    }

    static var requiredGranted: Bool {
        AXIsProcessTrusted() && IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
    }

    var needsSetup: Bool {
        refreshRequired()
        return state.needsSetup(completed: UserDefaults.standard.bool(forKey: Self.completedKey))
    }

    func refreshRequired() {
        guard !Self.isPreview else { return }
        var updated = state
        updated.accessibility = AXIsProcessTrusted()
        updated.inputMonitoring = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        guard updated != state else { return }
        state = updated
        NotificationCenter.default.post(name: Self.changed, object: self)
    }

    func refresh() {
        refreshRequired()
        guard !Self.isPreview else { return }
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async { self?.state.notifications = settings.authorizationStatus }
        }
    }

    func requestAccessibility() {
        guard !Self.isPreview else { return }
        Utils.requireAccessibilityPermissions()
        openSettings("Privacy_Accessibility")
    }

    func requestInputMonitoring() {
        guard !Self.isPreview else { return }
        let status = IOHIDCheckAccess(kIOHIDRequestTypeListenEvent)
        if status == kIOHIDAccessTypeUnknown {
            IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        } else {
            openSettings("Privacy_ListenEvent")
        }
        refreshRequired()
    }

    func requestNotifications() {
        guard !Self.isPreview, !requestingNotifications else { return }
        if state.notifications == .denied {
            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")!)
            return
        }
        requestingNotifications = true
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] _, _ in
            DispatchQueue.main.async {
                self?.requestingNotifications = false
                self?.refresh()
            }
        }
    }

    func completeSetup() -> Bool {
        refreshRequired()
        guard !Self.isPreview, state.requiredGranted else { return false }
        UserDefaults.standard.set(true, forKey: Self.completedKey)
        return true
    }

    private func openSettings(_ pane: String) {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
    }
}
