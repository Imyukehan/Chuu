import AppKit
import SwiftUI
import UserNotifications
import OSLog
import ImageIO
import QuartzCore

@available(macOS 14.0, *)
final class MouseAlerts: NSObject, UNUserNotificationCenterDelegate {
    static let shared = MouseAlerts()
    static let connectionsKey = "chuu.connectionAlerts"
    static let lowBatteryKey = "chuu.lowBatteryAlerts"
    private static let warnedKey = "chuu.lowBatteryWarnedDevices"
    private var policy = MouseAlertPolicy()
    private var panel: MouseConnectionPanel?
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
        content.body = String(format: NSLocalizedString("Battery low: %d%%", tableName: "Chuu", comment: "Low battery notification"), device.battery ?? 0)
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
            DispatchQueue.main.async { ChuuWindow.shared.present(deviceID: id) }
        }
        completionHandler()
    }

    func present(_ device: MouseSnapshot) {
        guard canPresent, let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main else { return }
        dismiss()
        var visibleFrame = screen.visibleFrame
        let safeTop = min(visibleFrame.maxY, screen.frame.maxY - screen.safeAreaInsets.top)
        visibleFrame.size.height = safeTop - visibleFrame.minY
        let capsuleFrame = MouseConnectionLayout.frame(
            in: visibleFrame, statusItemFrame: StatusItemManager.visibleAnchor(on: screen))
        // Leave room for the system glass edge instead of clipping it at the window boundary.
        let frame = capsuleFrame.insetBy(dx: -8, dy: -8)
        let panel = MouseConnectionPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.title = "Chuu"
        panel.contentView = MouseConnectionSurface.makeView(device: device, close: { [weak self] in self?.dismiss(animated: true) })
        panel.setAccessibilityLabel(NSLocalizedString("Connection popup", tableName: "Chuu", comment: "Popup"))
        self.panel = panel
        panel.reveal(at: frame, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        let dismissal = DispatchWorkItem { [weak self] in self?.dismiss(animated: true) }
        self.dismissal = dismissal
        DispatchQueue.main.asyncAfter(deadline: .now() + 5, execute: dismissal)
    }

    private func dismiss(animated: Bool = false) {
        dismissal?.cancel()
        dismissal = nil
        guard let panel else { return }
        if animated {
            panel.conceal(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) { [weak self, weak panel] in
                if self?.panel === panel { self?.panel = nil }
            }
        } else {
            // Lock, sleep, device removal and replacement must hide immediately.
            panel.orderOut(nil)
            self.panel = nil
        }
    }
}

final class MouseConnectionPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    private var dismissing = false

    func reveal(at frame: NSRect, reduceMotion: Bool) {
        animationBehavior = .none
        alphaValue = 0
        setFrame(frame.offsetBy(dx: 0, dy: MouseConnectionMotion.offset(reduceMotion: reduceMotion)), display: false)
        orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MouseConnectionMotion.duration(appearing: true, reduceMotion: reduceMotion)
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(frame, display: true)
        }
    }

    func conceal(reduceMotion: Bool, completion: @escaping () -> Void) {
        guard !dismissing else { return }
        dismissing = true
        let destination = frame.offsetBy(dx: 0, dy: MouseConnectionMotion.offset(reduceMotion: reduceMotion))
        NSAnimationContext.runAnimationGroup { context in
            context.duration = MouseConnectionMotion.duration(appearing: false, reduceMotion: reduceMotion)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            animator().alphaValue = 0
            animator().setFrame(destination, display: true)
        } completionHandler: { [self] in
            orderOut(nil)
            completion()
        }
    }
}

enum MouseConnectionMotion {
    static func duration(appearing: Bool, reduceMotion: Bool) -> TimeInterval {
        reduceMotion ? 0.12 : (appearing ? 0.42 : 0.32)
    }
    static func offset(reduceMotion: Bool) -> CGFloat { reduceMotion ? 0 : 8 }
}

@available(macOS 14.0, *)
enum MouseConnectionSurface {
    static func makeView(device: MouseSnapshot, close: @escaping () -> Void) -> NSView {
        let size = MouseConnectionLayout.size
        let root = NSView(frame: NSRect(origin: .zero, size: NSSize(width: size.width + 16, height: size.height + 16)))
        let content = NSHostingView(rootView: MouseConnectionCard(device: device, close: close))
        let surface: NSView
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            // Regular responds to the system glass slider in our macOS 27 panel checks.
            glass.style = .regular
            glass.cornerRadius = MouseConnectionLayout.size.height / 2
            glass.contentView = content
            surface = glass
        } else {
            let effect = NSVisualEffectView()
            effect.material = .hudWindow
            effect.blendingMode = .behindWindow
            effect.state = .active
            effect.wantsLayer = true
            effect.layer?.cornerRadius = MouseConnectionLayout.size.height / 2
            effect.layer?.masksToBounds = true
            effect.addSubview(content)
            content.frame = NSRect(origin: .zero, size: MouseConnectionLayout.size)
            content.autoresizingMask = [.width, .height]
            surface = effect
        }
        surface.frame = NSRect(origin: NSPoint(x: 8, y: 8), size: MouseConnectionLayout.size)
        root.addSubview(surface)
        return root
    }
}

enum MouseConnectionLayout {
    static let size = NSSize(width: 236, height: 52)

    static func frame(in visibleFrame: NSRect, statusItemFrame: NSRect? = nil) -> NSRect {
        let margin: CGFloat = 12
        let width = min(size.width, max(0, visibleFrame.width - margin * 2))
        // Ignore stale/off-screen anchors (including menu-bar managers' hidden items).
        let anchor = statusItemFrame.flatMap { frame -> NSRect? in
            guard frame.width > 0, frame.height > 0,
                  frame.minX >= visibleFrame.minX, frame.maxX <= visibleFrame.maxX,
                  frame.maxY >= visibleFrame.maxY, frame.minY <= visibleFrame.maxY + 64 else { return nil }
            return frame
        }
        let centerX = anchor?.midX ?? visibleFrame.midX
        let x = min(max(centerX - width / 2, visibleFrame.minX + margin), visibleFrame.maxX - width - margin)
        return NSRect(x: x,
                      y: visibleFrame.maxY - size.height - 12,
                      width: width, height: size.height)
    }
}

enum MouseConnectionArtwork {
    private static let cache = NSCache<NSString, NSImage>()

    static func image(for device: MouseSnapshot) -> NSImage? {
        let names = device.model == "g502x" ? ["G502RenderTop", device.imageName] : [device.imageName]
        for name in names where !name.isEmpty {
            if let image = cache.object(forKey: name as NSString) { return image }
            guard let source = NSImage(named: name), let image = thumbnail(from: source) else { continue }
            cache.setObject(image, forKey: name as NSString)
            return image
        }
        return nil
    }

    static func thumbnail(from image: NSImage) -> NSImage? {
        guard let data = image.tiffRepresentation,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let result = NSImage(size: .zero)
        // Supply pixel-matched representations so AppKit does not minify a full product render.
        for scale in [1, 2] {
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: 32 * scale,
                kCGImageSourceShouldCacheImmediately: true
            ]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
            let rep = NSBitmapImageRep(cgImage: cg)
            let points = NSSize(width: CGFloat(cg.width) / CGFloat(scale), height: CGFloat(cg.height) / CGFloat(scale))
            if scale == 1 { result.size = points }
            rep.size = result.size
            result.addRepresentation(rep)
        }
        return result
    }
}

@available(macOS 14.0, *)
struct MouseConnectionCard: View {
    let device: MouseSnapshot
    let close: () -> Void
    var body: some View {
        Button(action: close) {
            HStack(spacing: 8) {
                Group {
                    if let image = MouseConnectionArtwork.image(for: device) {
                        Image(nsImage: image).interpolation(.high)
                    } else {
                        Image(systemName: "computermouse.fill").font(.system(size: 24, weight: .light))
                    }
                }.frame(width: 28, height: 32).accessibilityHidden(true)

                VStack(spacing: 2) {
                    Text(device.name).font(.system(size: 13, weight: .semibold))
                        .lineLimit(1).truncationMode(.middle)
                    Text(NSLocalizedString(device.charging ? "Charging" : "Connected", tableName: "Chuu", comment: "Connection popup"))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)

                MouseConnectionBatteryRing(battery: device.battery)
            }
            .padding(.horizontal, 10)
            .frame(width: MouseConnectionLayout.size.width, height: MouseConnectionLayout.size.height)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(NSLocalizedString("Close", tableName: "Chuu", comment: "Close popup"))
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
            Circle().stroke(.primary.opacity(0.08), lineWidth: 3.5)
            Circle().trim(from: 0, to: CGFloat(percentage ?? 0) / 100)
                .stroke(tint, style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(percentage.map(String.init) ?? "—")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .monospacedDigit().foregroundStyle(.secondary)
        }
        .padding(2).frame(width: 36, height: 36)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NSLocalizedString("Mouse battery", tableName: "Chuu", comment: "Battery ring"))
        .accessibilityValue(percentage.map { "\($0)%" } ?? NSLocalizedString("Battery unavailable", tableName: "Chuu", comment: "Unknown battery"))
    }
}

@available(macOS 14.0, *)
struct MouseAlertSettings: View {
    @ObservedObject var model: ChuuModel
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
    private func tr(_ key: String) -> String { NSLocalizedString(key, tableName: "Chuu", comment: "Alert settings") }
}
