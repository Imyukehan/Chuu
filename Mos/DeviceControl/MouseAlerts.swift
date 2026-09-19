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
        let frame = MouseConnectionLayout.frame(in: screen.visibleFrame)
        let panel = MouseConnectionPanel(contentRect: frame,
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
        panel.setFrame(frame, display: false)
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

enum MouseConnectionLayout {
    static let size = NSSize(width: 300, height: 64)

    static func frame(in visibleFrame: NSRect) -> NSRect {
        NSRect(x: visibleFrame.maxX - size.width - 16,
               y: visibleFrame.maxY - size.height - 8,
               width: size.width, height: size.height)
    }
}

@available(macOS 14.0, *)
struct MouseConnectionCard: View {
    let device: MouseSnapshot
    let close: () -> Void
    var body: some View {
        Button(action: close) {
            HStack(spacing: 10) {
                Group {
                    if let image = connectionImage {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        Image(systemName: "computermouse.fill").font(.system(size: 27, weight: .light))
                    }
                }.frame(width: 36, height: 42).accessibilityHidden(true)

                VStack(spacing: 3) {
                    Text(device.name).font(.system(size: 14, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle)
                    Text(NSLocalizedString(device.charging ? "Charging" : "Connected", tableName: "MouseControl", comment: "Connection popup"))
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                MouseConnectionBatteryRing(battery: device.battery)
            }
            .padding(.horizontal, 12)
            .frame(width: MouseConnectionLayout.size.width, height: MouseConnectionLayout.size.height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .modifier(ConnectionCardSurface())
        .help(NSLocalizedString("Close", tableName: "MouseControl", comment: "Close popup"))
    }

    private var connectionImage: NSImage? {
        if device.model == "g502x", let image = NSImage(named: "G502RenderTop") { return image }
        return device.imageName.isEmpty ? nil : NSImage(named: device.imageName)
    }
}

@available(macOS 14.0, *)
private struct MouseConnectionBatteryRing: View {
    let battery: Int?
    private var percentage: Int? { battery.flatMap { (0...100).contains($0) ? $0 : nil } }
    private var tint: Color {
        guard let percentage else { return .secondary }
        return percentage <= 10 ? .red : percentage <= 20 ? .orange : .green
    }

    var body: some View {
        ZStack {
            Circle().stroke(.primary.opacity(0.08), lineWidth: 4.5)
            Circle().trim(from: 0, to: CGFloat(percentage ?? 0) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(percentage.map(String.init) ?? "—")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(3).frame(width: 44, height: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("Mouse battery", tableName: "MouseControl", comment: "Battery ring"))
        .accessibilityValue(percentage.map { "\($0)%" } ?? NSLocalizedString("Battery unavailable", tableName: "MouseControl", comment: "Unknown battery"))
    }
}

@available(macOS 14.0, *)
private struct ConnectionCardSurface: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content.glassEffect(.regular, in: Capsule())
        } else {
            content.background(.regularMaterial, in: Capsule())
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
