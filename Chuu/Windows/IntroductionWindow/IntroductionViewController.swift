// Based on the Mos introduction window by Caldis. CC BY-NC 4.0.
import Cocoa
import SwiftUI

class IntroductionViewController: NSViewController {
    private var checkerTimer: Timer?
    private var isManuallyOpened = false
    private var finished = false

    func setManuallyOpened(_ manually: Bool) { isManuallyOpened = manually }

    override func viewDidLoad() {
        super.viewDidLoad()
        let content = NSHostingView(rootView: ChuuPermissionSetupView(permissions: .shared, finish: { [weak self] in
            self?.finish()
        }))
        content.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            content.topAnchor.constraint(equalTo: view.topAnchor),
            content.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        NotificationCenter.default.addObserver(self, selector: #selector(refresh),
                                              name: NSApplication.didBecomeActiveNotification, object: nil)
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        refresh()
        checkerTimer?.invalidate()
        checkerTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            ChuuPermissions.shared.refreshRequired()
            guard let self, NSApp.isActive, !self.isManuallyOpened,
                  ChuuPermissions.shared.state.allDecided else { return }
            self.finish()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        checkerTimer?.invalidate()
        checkerTimer = nil
    }

    deinit {
        checkerTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func refresh() { ChuuPermissions.shared.refresh() }

    private func finish() {
        guard !finished, ChuuPermissions.shared.completeSetup() else { return }
        finished = true
        let wasManual = isManuallyOpened
        view.window?.close()
        if !wasManual { ChuuWindow.shared.present() }
    }
}

struct ChuuPermissionSetupView: View {
    @ObservedObject var permissions: ChuuPermissions
    @State private var showRecovery = false
    var finish: () -> Void

    var body: some View {
        VStack(spacing: 22) {
            PermissionAppIcon().frame(width: 72, height: 72)
                .help(tr("Drag this icon into the permission list if Chuu is missing."))
            Text(tr("Set Up Chuu")).font(.title2.weight(.semibold))
            VStack(spacing: 0) {
                row("Accessibility", detail: "Scrolling and shortcuts", symbol: "accessibility",
                    granted: permissions.state.accessibility, action: permissions.requestAccessibility)
                Divider()
                row("Input Monitoring", detail: "Mouse status and battery", symbol: "computermouse",
                    granted: permissions.state.inputMonitoring, action: permissions.requestInputMonitoring)
                Divider()
                row("Notifications", detail: "Low battery alerts (optional)", symbol: "bell",
                    granted: [.authorized, .provisional].contains(permissions.state.notifications),
                    action: permissions.requestNotifications)
            }
            HStack(spacing: 16) {
                Button { showRecovery = true } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.plain)
                .help(tr("Permission not working?"))
                .accessibilityLabel(tr("Permission not working?"))
                .popover(isPresented: $showRecovery) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(tr("Permission not working?")).font(.headline)
                        Text(tr(ChuuPermissions.recoveryInstructions)).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(tr("Input Monitoring"), action: permissions.requestInputMonitoring)
                            Button(tr("Accessibility"), action: permissions.requestAccessibility)
                        }
                    }.padding(20).frame(width: 360)
                }
                Button(tr("Continue"), action: finish)
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .disabled(!permissions.state.requiredGranted)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28).padding(.top, 16)
        .frame(width: 460, height: 440)
    }

    private func row(_ title: String, detail: String, symbol: String, granted: Bool,
                     action: @escaping () -> Void) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.title3).frame(width: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(tr(title)).fontWeight(.medium)
                Text(tr(detail)).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if granted {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    .accessibilityLabel(tr("Authorized")).frame(width: 88)
            } else {
                Button(tr("Set Up"), action: action).frame(width: 88)
            }
        }.frame(height: 62)
    }

    private func tr(_ key: String) -> String { NSLocalizedString(key, tableName: "Chuu", comment: "Permission setup") }
}

private struct PermissionAppIcon: NSViewRepresentable {
    func makeNSView(context: Context) -> DraggingImageView {
        let view = DraggingImageView()
        let icon = NSApplication.shared.applicationIconImage.copy() as! NSImage
        icon.size = NSSize(width: 72, height: 72)
        view.image = icon
        view.imageScaling = .scaleProportionallyUpOrDown
        view.isEnabled = true
        view.setAccessibilityLabel("Chuu")
        return view
    }
    func updateNSView(_ nsView: DraggingImageView, context: Context) {}
}
