import AppKit
import SwiftUI
import UserNotifications
import OSLog

@available(macOS 14.0, *)
final class MouseAlerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MouseAlerts()
    static let connectionsKey = "chuu.connectionAlerts"
    static let lowBatteryKey = "chuu.lowBatteryAlerts"
    private static let warnedKey = "chuu.lowBatteryWarnedDevices"
    private var policy = MouseAlertPolicy()
    private var panel: NSPanel?
    private var dismissal: DispatchWorkItem?
    private var sleeping = false
    private var displaySleeping = false
    private var inactiveSession = false
    private var screenLocked = false
    private var screenSaver = false
    private var pendingNotifications: Set<String> = []
    private var latestDevices: [MouseSnapshot] = []

    private var canPresent: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return !sleeping && !displaySleeping && !inactiveSession && !screenLocked && !screenSaver
            && (session?[kCGSessionOnConsoleKey as String] as? Bool == true)
            && (session?["CGSSessionScreenIsLocked"] as? Bool != true)
    }

    private override init() {
        super.init()
        policy.warnedDevices = Set(UserDefaults.standard.stringArray(forKey: Self.warnedKey) ?? [])
        UserDefaults.standard.register(defaults: [Self.connectionsKey: true, Self.lowBatteryKey: false])
        UNUserNotificationCenter.current().delegate = self
        for name in [NSWorkspace.screensDidSleepNotification, NSWorkspace.screensDidWakeNotification,
                     NSWorkspace.sessionDidResignActiveNotification, NSWorkspace.sessionDidBecomeActiveNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sessionChanged(_:)), name: name, object: nil)
        }
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked",
                     "com.apple.screensaver.didstart", "com.apple.screensaver.didstop"] {
            DistributedNotificationCenter.default().addObserver(self, selector: #selector(sessionChanged(_:)),
                                                                name: Notification.Name(name), object: nil)
        }
    }

    func suspend() { sleeping = true; dismiss(); policy.rebaseline() }
    func resume() { sleeping = false; policy.rebaseline() }
    func deviceRemoved(_ id: String) { policy.deviceRemoved(id); dismiss() }

    @objc private func sessionChanged(_ notification: Notification) {
        switch notification.name {
        case NSWorkspace.screensDidSleepNotification: displaySleeping = true
        case NSWorkspace.screensDidWakeNotification: displaySleeping = false
        case NSWorkspace.sessionDidResignActiveNotification: inactiveSession = true
        case NSWorkspace.sessionDidBecomeActiveNotification: inactiveSession = false
        case Notification.Name("com.apple.screenIsLocked"): screenLocked = true
        case Notification.Name("com.apple.screenIsUnlocked"): screenLocked = false
        case Notification.Name("com.apple.screensaver.didstart"): screenSaver = true
        case Notification.Name("com.apple.screensaver.didstop"): screenSaver = false
        default: return
        }
        dismiss()
        policy.rebaseline()
    }

    func update(_ devices: [MouseSnapshot]) {
        latestDevices = devices
        guard canPresent else { policy.rebaseline(); return }
        let events = policy.consume(devices, at: Date(), lowBatteryEnabled: UserDefaults.standard.bool(forKey: Self.lowBatteryKey))
        UserDefaults.standard.set(Array(policy.warnedDevices), forKey: Self.warnedKey)
        for event in events {
            switch event {
            case .connected(let id):
                if UserDefaults.standard.bool(forKey: Self.connectionsKey), let device = devices.first(where: { $0.id == id }) {
                    present(device)
                }
            case .lowBattery(let id):
                if let device = devices.first(where: { $0.id == id }) { sendLowBattery(device) }
            }
        }
    }

    func enableLowBattery(_ completion: @escaping (Bool) -> Void) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { allowed, _ in
            DispatchQueue.main.async { completion(allowed) }
        }
    }

    private func sendLowBattery(_ device: MouseSnapshot) {
        guard pendingNotifications.insert(device.id).inserted else { return }
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                guard let self else { return }
                guard settings.authorizationStatus == .authorized,
                      self.canPresent, UserDefaults.standard.bool(forKey: Self.lowBatteryKey),
                      let current = self.latestDevices.first(where: { $0.id == device.id }),
                      current.online, current.isFresh(at: Date()), !current.charging,
                      let battery = current.battery, (0...20).contains(battery) else {
                    self.pendingNotifications.remove(device.id)
                    return
                }
                self.postLowBattery(current, center: center)
            }
        }
    }

    private func postLowBattery(_ device: MouseSnapshot, center: UNUserNotificationCenter) {
        let content = UNMutableNotificationContent()
        content.title = device.name
        content.body = String(format: NSLocalizedString("Battery low: %d%%", tableName: "MouseControl", comment: "Low battery notification"), device.battery ?? 0)
        content.sound = .default
        content.userInfo = ["mouseID": device.id]
        let request = UNNotificationRequest(identifier: "chuu.low-battery.\(device.id)", content: content, trigger: nil)
        center.add(request) { [weak self] error in
            if let error {
                os_log("Notification failed: %{public}@", log: OSLog(subsystem: "moe.khan.MouseControl", category: "Alerts"),
                       type: .error, error.localizedDescription)
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.pendingNotifications.remove(device.id)
                if error == nil {
                    self.policy.didNotifyLowBattery(device.id)
                    UserDefaults.standard.set(Array(self.policy.warnedDevices), forKey: Self.warnedKey)
                }
            }
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
            let id = response.notification.request.content.userInfo["mouseID"] as? String
            DispatchQueue.main.async { MouseControlWindow.shared.present(deviceID: id) }
        }
        completionHandler()
    }

    func present(_ device: MouseSnapshot) {
        guard canPresent, let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        dismiss()
        let size = NSSize(width: 320, height: 260)
        let panel = MouseConnectionPanel(contentRect: NSRect(origin: .zero, size: size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.title = "Chuu"
        panel.contentView = NSHostingView(rootView: MouseConnectionCard(device: device, close: { [weak self] in self?.dismiss() }))
        panel.setAccessibilityLabel(NSLocalizedString("Connection popup", tableName: "MouseControl", comment: "Popup"))
        panel.setFrameOrigin(NSPoint(x: screen.visibleFrame.midX - size.width / 2, y: screen.visibleFrame.minY + 36))
        panel.orderFrontRegardless()
        self.panel = panel
        let dismissal = DispatchWorkItem { [weak self] in self?.dismiss() }
        self.dismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: dismissal)
    }

    private func dismiss() {
        dismissal?.cancel()
        dismissal = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

final class MouseConnectionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@available(macOS 14.0, *)
private struct MouseConnectionCard: View {
    let device: MouseSnapshot
    let close: () -> Void
    var body: some View {
        VStack(spacing: 10) {
            if let image = connectionImage {
                Image(nsImage: image).resizable().scaledToFit().frame(height: 135)
            } else {
                Image(systemName: "computermouse.fill").font(.system(size: 68, weight: .light)).frame(height: 135)
            }
            Text(device.name).font(.headline).lineLimit(1).truncationMode(.middle)
            HStack(spacing: 8) {
                Text(NSLocalizedString("Connected", tableName: "MouseControl", comment: "Connection popup"))
                Text(device.connectionLabel)
                if let battery = device.battery {
                    Label("\(battery)%", systemImage: device.charging ? "battery.100percent.bolt" : "battery.100percent")
                }
            }.font(.callout).foregroundStyle(.secondary)
        }.padding(24).frame(width: 320, height: 260)
            .modifier(ConnectionCardSurface())
            .overlay(alignment: .topTrailing) {
                Button(action: close) { Image(systemName: "xmark").frame(width: 24, height: 24) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).padding(12)
                    .help(NSLocalizedString("Close", tableName: "MouseControl", comment: "Close popup"))
            }
    }

    private var connectionImage: NSImage? {
        if device.model == "g502x", let image = NSImage(named: "G502RenderTop") { return image }
        return device.imageName.isEmpty ? nil : NSImage(named: device.imageName)
    }
}

@available(macOS 14.0, *)
private struct ConnectionCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24))
        } else {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

@available(macOS 14.0, *)
struct MouseAlertSettings: View {
    @ObservedObject var model: MouseControlModel
    @AppStorage(MouseAlerts.connectionsKey) private var connections = true
    @AppStorage(MouseAlerts.lowBatteryKey) private var lowBattery = false
    @State private var permissionDenied = false

    var body: some View {
        HStack(spacing: 20) {
            Toggle(tr("Connection popup"), isOn: $connections)
            Button {
                if let device = model.selected { MouseAlerts.shared.present(device) }
            } label: { Image(systemName: "play.circle") }
                .help(tr("Preview connection popup")).disabled(model.selected?.online != true)
            Divider().frame(height: 20)
            Toggle(tr("Low battery alert (20%)"), isOn: Binding(get: { lowBattery }, set: { enabled in
                if !enabled { lowBattery = false; return }
                MouseAlerts.shared.enableLowBattery { allowed in
                    lowBattery = allowed
                    permissionDenied = !allowed
                    if allowed { model.refresh() }
                }
            }))
        }.toggleStyle(.switch).controlSize(.small).frame(maxWidth: 840)
            .alert(tr("Allow notifications in System Settings"), isPresented: $permissionDenied) {
                Button(tr("OK"), role: .cancel) {}
            }
    }
    private func tr(_ key: String) -> String { NSLocalizedString(key, tableName: "MouseControl", comment: "Alert settings") }
}
