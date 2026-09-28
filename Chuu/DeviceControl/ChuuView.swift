import SwiftUI
import AppKit

@available(macOS 14.0, *)
struct ChuuView: View {
    @ObservedObject var model: ChuuModel
    @ObservedObject var navigation: ChuuNavigation
    @ObservedObject private var permissions = ChuuPermissions.shared
    @State private var selectedButton = 0
    @State private var sideView = false
    @State private var assignment = -1
    @State private var showOnboardEditor = false
    @State private var showWidgetHelp = false

    private let buttonNames = ["Left click", "Right click", "Middle click", "Back", "DPI shift", "Forward",
                               "Tilt left", "Tilt right", "Profile cycle", "DPI +", "DPI -"]

    var body: some View {
        VStack(spacing: 0) {
            if navigation.page == .device {
                devicePage
            } else {
                VStack(spacing: 16) {
                    if !permissions.state.requiredGranted {
                        Button(tr("Permissions…")) { IntroductionWindowController.present(manually: true) }
                            .buttonStyle(.borderedProminent)
                    }
                    if navigation.page == .general {
                        Spacer(minLength: 0)
                        MouseAlertSettings(model: model)
                        if let issue = model.widgetSharingIssue, let title = issue.messageKey {
                            HStack {
                                Label(tr(title), systemImage: "exclamationmark.triangle")
                                    .foregroundStyle(.secondary)
                                Button { showWidgetHelp = true } label: {
                                    Image(systemName: "questionmark.circle")
                                }
                                .help(tr("Widget sharing"))
                                .accessibilityLabel(tr("Widget sharing"))
                                .popover(isPresented: $showWidgetHelp) {
                                    Text(tr(issue == .unsupportedBuild
                                        ? "This test build keeps battery data in the app only. Widget sharing requires the app and widget to be signed by the team that owns their App Group. Input Monitoring permission does not enable sharing."
                                        : "The app could not write the shared battery cache. Restart Chuu and check that the app and widget come from the same signed installation."))
                                        .fixedSize(horizontal: false, vertical: true)
                                        .padding(20).frame(width: 340)
                                }
                            }.font(.callout)
                        }
                        ChuuPreferencesPane(identifier: "general").frame(maxWidth: 840).frame(height: 160)
                        Spacer(minLength: 0)
                    } else {
                        ChuuPreferencesPane(identifier: navigation.page.rawValue).id(navigation.page)
                            .frame(maxWidth: 840, maxHeight: .infinity)
                    }
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MouseWindowMaterial().ignoresSafeArea())
        .alert(tr("Mouse Control"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            if model.errorNeedsPermissions {
                Button(tr("Permissions…")) {
                    model.error = nil
                    IntroductionWindowController.present(manually: true)
                }
            }
            Button(tr("OK"), role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onChange(of: selectedButton) { _, _ in assignment = -1 }
        .onChange(of: model.selectedID) { _, _ in
            showOnboardEditor = false
            assignment = -1; selectedButton = 0; sideView = false
        }
        .onChange(of: navigation.page) { _, _ in showOnboardEditor = false }
        .onChange(of: showOnboardEditor) { _, _ in assignment = -1 }
        .onChange(of: model.profile) { old, new in
            if old?.mapping(selectedButton) != new?.mapping(selectedButton) { assignment = -1 }
        }
    }

    @ViewBuilder private var devicePage: some View {
        if let device = model.selected {
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 9) {
                        if model.devices.count > 1 {
                            Picker("", selection: $model.selectedID) {
                                ForEach(model.devices) { Text($0.name).tag(Optional($0.id)) }
                            }.labelsHidden().frame(maxWidth: 240)
                        } else {
                            Text(device.name).font(.system(size: 26, weight: .semibold))
                        }
                        HStack(spacing: 6) {
                            Circle().fill(device.online ? Color.green : Color.secondary).frame(width: 6, height: 6)
                            Text(device.online ? tr("Connected") : tr("Sleeping or unavailable"))
                            Text("· \(device.connectionLabel)")
                        }.font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 5) {
                        HStack(spacing: 10) {
                            Image(systemName: device.charging ? "battery.100percent.bolt" : batterySymbol(device.battery))
                                .font(.title2).foregroundStyle(device.battery ?? 100 < 20 ? .orange : .green)
                            Text(device.battery.map { "\($0)%" } ?? "—")
                                .font(.system(size: 27, weight: .medium, design: .rounded)).monospacedDigit()
                        }
                        if !device.online, device.battery != nil {
                            Text(device.updatedAt, style: .time).font(.caption).foregroundStyle(.secondary)
                        } else if device.charging { Text(tr("Charging")).font(.caption).foregroundStyle(.secondary) }
                    }
                }.padding(.horizontal, 42).padding(.top, 26).padding(.bottom, 12)

                HStack(spacing: 20) {
                    VStack(spacing: 0) {
                        MouseArtwork(model: device.model, side: sideView, selected: $selectedButton,
                                     interactive: device.online,
                                     onSelect: { _ in showOnboardEditor = true })
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(device.online ? 1 : 0.45)
                        if device.model == "g502x" {
                            ChuuModePicker(titles: [tr("Top"), tr("Side")], isSecondSelected: $sideView)
                                .frame(width: 152, height: 32)
                                .padding(.bottom, 28)
                        }
                    }
                    buttonSettings(for: device).padding(.trailing, 40)
                }.frame(maxHeight: .infinity)
            }
        } else {
            HStack(spacing: 28) {
                MouseArtwork(model: "generic", side: false, selected: $selectedButton)
                    .foregroundStyle(.tertiary).help(tr("No mouse connected"))
                VStack(spacing: 16) {
                    Text(tr("Buttons")).font(.headline)
                    shortcutSettings
                }.frame(width: 470).padding(.vertical, 28)
            }.padding(.horizontal, 40)
        }
    }

    private func buttonSettings(for device: MouseSnapshot) -> some View {
        VStack(spacing: 12) {
            HStack {
                Text(tr("Buttons")).font(.headline)
                Spacer()
                if device.model == "g502x" {
                    Button { showOnboardEditor.toggle() } label: {
                        Image(systemName: "slider.horizontal.3")
                    }
                    .help(tr("Onboard buttons"))
                    .accessibilityLabel(tr("Onboard buttons"))
                    .popover(isPresented: $showOnboardEditor, arrowEdge: .bottom) {
                        onboardEditor
                    }
                }
            }
            shortcutSettings
            if device.model == "g502x", let profile = model.profile {
                Divider()
                HStack {
                    Label("RGB", systemImage: "lightbulb")
                    Spacer()
                    Toggle("RGB", isOn: Binding(get: { !profile.lightsOff }, set: { model.save(lightingEnabled: $0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .disabled(model.busy || !device.online)
                }.padding(.vertical, 4)
            }
        }.frame(width: 470)
            .padding(.top, 10).padding(.bottom, 20)
    }

    private var shortcutSettings: some View {
        VStack(spacing: 12) {
            if !permissions.state.requiredGranted {
                Button(tr("Permissions…")) { IntroductionWindowController.present(manually: true) }
                    .buttonStyle(.borderedProminent)
            }
            ChuuPreferencesPane(identifier: "buttons")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var onboardEditor: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(tr("Onboard buttons")).font(.headline)
            Picker(tr("Buttons"), selection: $selectedButton) {
                ForEach(buttonNames.indices, id: \.self) { index in
                    Text(tr(buttonNames[index])).tag(index)
                }
            }
            .onChange(of: selectedButton) { _, index in sideView = [3, 4, 5].contains(index) }
            if let profile = model.profile {
                HStack(spacing: 12) {
                    Picker(tr(buttonNames[selectedButton]), selection: $assignment) {
                        Text(mappingName(profile.mapping(selectedButton), index: selectedButton)).tag(-1)
                        Text(tr("Default")).tag(0)
                        ForEach(1...8, id: \.self) { value in
                            Text(value > 3 ? "Mouse \(value - 1)" : tr(buttonNames[value - 1])).tag(value)
                        }
                    }.labelsHidden()
                        .disabled(selectedButton == 0 || model.busy || model.selected?.online != true)
                        .frame(maxWidth: .infinity)
                    if model.busy { ProgressView().controlSize(.small) }
                    applyButton.disabled(assignment < 0 || selectedButton == 0 || model.busy || model.selected?.online != true)
                }
            } else if let error = model.profileError {
                Button { model.loadProfile() } label: { Label(tr("Read profile"), systemImage: "arrow.clockwise") }
                    .help(error).disabled(model.busy || model.selected?.online != true)
            } else {
                ProgressView().controlSize(.small)
            }
        }.padding(20).frame(width: 340)
    }

    @ViewBuilder private var applyButton: some View {
        if #available(macOS 26.0, *) {
            Button(tr("Apply"), action: applyMapping).buttonStyle(.glassProminent)
        } else {
            Button(tr("Apply"), action: applyMapping).buttonStyle(.borderedProminent)
        }
    }

    private func applyMapping() {
        guard assignment >= 0 else { return }
        let bytes = assignment == 0 ? OnboardMouseProfile.defaults[selectedButton] : OnboardMouseProfile.mouseMappings[assignment - 1]
        model.save(button: selectedButton, mapping: bytes)
    }

    private func mappingName(_ bytes: [UInt8]?, index: Int) -> String {
        guard let bytes else { return "—" }
        if let mouse = OnboardMouseProfile.mouseMappings.firstIndex(of: bytes) {
            return mouse > 2 ? "Mouse \(mouse)" : tr(buttonNames[mouse])
        }
        if bytes == OnboardMouseProfile.defaults[index] { return tr("Default") }
        return tr("Custom")
    }

    private func batterySymbol(_ value: Int?) -> String {
        guard let value else { return "battery.0percent" }
        return "battery.\(value > 75 ? 100 : value > 50 ? 75 : value > 25 ? 50 : value > 10 ? 25 : 0)percent"
    }
    private func tr(_ key: String) -> String { NSLocalizedString(key, tableName: "Chuu", comment: "Mouse Control") }
}

@available(macOS 14.0, *)
struct MouseArtwork: View {
    let model: String
    let side: Bool
    @Binding var selected: Int
    var interactive = true
    var onSelect: ((Int) -> Void)?

    private var hasDriverRender: Bool {
        model == "g502x" && NSImage(named: side ? "G502RenderSide" : "G502RenderTop") != nil
    }

    private var image: NSImage? {
        #if DEBUG
        // Process-only visual QA, without replacing the selected device or profile.
        if ProcessInfo.processInfo.arguments.contains("-ChuuPreviewGenericArtwork") { return nil }
        #endif
        if hasDriverRender { return NSImage(named: side ? "G502RenderSide" : "G502RenderTop") }
        guard ["g502x", "g7"].contains(model),
              let source = NSImage(named: model == "g502x" ? (side ? "G502Side" : "G502Top") : "G7") else { return nil }
        guard model == "g502x", let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return source }
        // Gallery files include transparent margins; crop only while rendering the view.
        let rect = side ? CGRect(x: 170, y: 280, width: 1030, height: 500) : CGRect(x: 390, y: 95, width: 590, height: 900)
        guard let cropped = cg.cropping(to: rect) else { return source }
        return NSImage(cgImage: cropped, size: rect.size)
    }

    private var points: [(Int, CGFloat, CGFloat)] {
        if hasDriverRender {
            if side { return [(5,0.54,0.48),(3,0.59,0.63),(4,0.29,0.39)] }
            return [(0,0.37,0.20),(1,0.78,0.20),(2,0.578,0.25),
                    (9,0.205,0.18),(10,0.185,0.30),(6,0.478,0.25),
                    (7,0.678,0.25),(8,0.583,0.47)]
        }
        if side { return [(5,0.47,0.48),(3,0.61,0.40),(4,0.375,0.70)] }
        return [(0,0.340,0.22),(1,0.704,0.24),(2,0.503,0.255),(9,0.205,0.18),(10,0.177,0.30),
                (6,0.433,0.28),(7,0.578,0.28),(8,0.513,0.445)]
    }

    var body: some View {
        GeometryReader { geometry in
            if let image {
                let aspect = image.size.width / image.size.height
                let height = min(geometry.size.height - 40, (geometry.size.width - 80) / aspect)
                let width = height * aspect
                ZStack {
                    Image(nsImage: image).resizable().scaledToFit()
                    if model == "g502x" && interactive {
                        if #available(macOS 26.0, *) {
                            GlassEffectContainer(spacing: 0) { hotspots(width: width, height: height) }
                        } else { hotspots(width: width, height: height) }
                    }
                }.frame(width: width, height: height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            } else {
                Image("GenericMouse").resizable().interpolation(.high).scaledToFit()
                    .frame(width: max(0, geometry.size.width - 80),
                           height: min(420, max(0, geometry.size.height - 48)))
                    .accessibilityHidden(true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func hotspots(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach(points, id: \.0) { point in
                Button { selected = point.0; onSelect?(point.0) } label: {
                    hotspot(selected: selected == point.0)
                }.buttonStyle(.plain)
                    .help(NSLocalizedString(["Left click","Right click","Middle click","Back","DPI shift","Forward","Tilt left","Tilt right","Profile cycle","DPI +","DPI -"][point.0], tableName: "Chuu", comment: "Mouse button"))
                    .accessibilityLabel(NSLocalizedString(["Left click","Right click","Middle click","Back","DPI shift","Forward","Tilt left","Tilt right","Profile cycle","DPI +","DPI -"][point.0], tableName: "Chuu", comment: "Mouse button"))
                    .accessibilityAddTraits(selected == point.0 ? .isSelected : [])
                    .position(x: width * point.1, y: height * point.2)
            }
        }.frame(width: width, height: height)
    }

    @ViewBuilder private func hotspot(selected: Bool) -> some View {
        let dot = Circle().fill(selected ? Color.accentColor : Color.primary.opacity(0.65))
            .frame(width: 6, height: 6).frame(width: 24, height: 24)
        if #available(macOS 26.0, *) {
            dot.glassEffect(.regular.interactive(), in: Circle())
        } else {
            dot.background(.ultraThinMaterial, in: Circle())
        }
    }
}
