import SwiftUI
import AppKit

@available(macOS 14.0, *)
struct MouseControlView: View {
    @ObservedObject var model: MouseControlModel
    @ObservedObject var navigation: MouseControlNavigation
    @State private var selectedButton = 4
    @State private var sideView = false
    @State private var assignment = -1

    private let buttonNames = ["Left click", "Right click", "Middle click", "Back", "DPI shift", "Forward",
                               "Tilt left", "Tilt right", "Profile cycle", "DPI +", "DPI -"]

    var body: some View {
        VStack(spacing: 0) {
            if navigation.page == .device {
                devicePage
            } else {
                VStack(spacing: 16) {
                    if !AXIsProcessTrusted() {
                        Button(tr("Enable Accessibility")) { Utils.requireAccessibilityPermissions() }
                            .buttonStyle(.borderedProminent)
                    }
                    MosPreferencesPane(identifier: navigation.page.rawValue).id(navigation.page)
                        .frame(maxWidth: 840, maxHeight: .infinity)
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(MouseWindowMaterial().ignoresSafeArea())
        .alert(tr("Mouse Control"), isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button(tr("OK"), role: .cancel) { model.error = nil }
        } message: { Text(model.error ?? "") }
        .onChange(of: selectedButton) { _, _ in assignment = -1 }
        .onChange(of: model.selectedID) { _, _ in assignment = -1; sideView = false }
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
                            Text("· 2.4 GHz")
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
                        MouseArtwork(model: device.model, side: sideView, selected: $selectedButton)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .opacity(device.online ? 1 : 0.45)
                        if device.model == "g502x" {
                            Picker("", selection: $sideView) {
                                Text(tr("Top")).tag(false)
                                Text(tr("Side")).tag(true)
                            }.pickerStyle(.segmented).labelsHidden().controlSize(.large).frame(width: 152)
                                .padding(.bottom, 28)
                        }
                    }
                    if device.model == "g502x" {
                        inspector.frame(width: 300).padding(.trailing, 40)
                    }
                }.frame(maxHeight: .infinity)
            }
        } else {
            Spacer()
            if model.scanning { ProgressView().controlSize(.small) }
            else { Image(systemName: "computermouse").font(.system(size: 38, weight: .ultraLight)).foregroundStyle(.tertiary).help(tr("No mouse connected")) }
            Spacer()
        }
    }

    private var inspector: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(tr("Buttons")).font(.headline)
                Spacer()
                if model.busy { ProgressView().controlSize(.small) }
            }
            VStack(spacing: 2) {
                ForEach(0..<11, id: \.self) { index in
                    Button {
                        selectedButton = index
                        if [3,4,5].contains(index) { sideView = true } else { sideView = false }
                    } label: {
                        HStack {
                            Text(tr(buttonNames[index]))
                            Spacer(minLength: 8)
                            Text(mappingName(model.profile?.mapping(index), index: index))
                                .foregroundStyle(.secondary).font(.system(size: 12))
                        }.padding(.horizontal, 10).frame(height: 29)
                            .contentShape(Rectangle())
                    }.buttonStyle(.plain)
                        .background(selectedButton == index ? Color.accentColor.opacity(0.10) : .clear, in: RoundedRectangle(cornerRadius: 6))
                        .accessibilityAddTraits(selectedButton == index ? .isSelected : [])
                }
            }
            Divider()
            if let profile = model.profile {
                HStack(spacing: 12) {
                    Picker(tr(buttonNames[selectedButton]), selection: $assignment) {
                        Text(mappingName(profile.mapping(selectedButton), index: selectedButton)).tag(-1)
                        Text(tr("Default")).tag(0)
                        ForEach(1...8, id: \.self) { value in
                            Text(value > 3 ? "Mouse \(value - 1)" : tr(buttonNames[value - 1])).tag(value)
                        }
                    }.disabled(selectedButton == 0 || model.busy).frame(maxWidth: .infinity)
                    applyButton.disabled(assignment < 0 || selectedButton == 0 || model.busy)
                }
                Divider().padding(.top, 4)
                HStack {
                    Label("RGB", systemImage: "lightbulb")
                    Spacer()
                    Toggle("RGB", isOn: Binding(get: { !profile.lightsOff }, set: { model.save(lightingEnabled: $0) }))
                        .labelsHidden().toggleStyle(.switch).controlSize(.small)
                        .disabled(model.busy || model.selected?.online != true)
                }
            } else if let error = model.profileError {
                Button { model.loadProfile() } label: { Label(tr("Read profile"), systemImage: "arrow.clockwise") }
                    .help(error).disabled(model.busy)
            }
            Spacer(minLength: 0)
        }.padding(.top, 22).padding(.bottom, 28)
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
    private func tr(_ key: String) -> String { NSLocalizedString(key, tableName: "MouseControl", comment: "Mouse Control") }
}

@available(macOS 14.0, *)
struct MouseArtwork: View {
    let model: String
    let side: Bool
    @Binding var selected: Int

    private var image: NSImage? {
        guard let source = NSImage(named: model == "g502x" ? (side ? "G502Side" : "G502Top") : "G7") else { return nil }
        guard model == "g502x", let cg = source.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return source }
        // Gallery files include transparent margins; crop only while rendering the view.
        let rect = side ? CGRect(x: 170, y: 280, width: 1030, height: 500) : CGRect(x: 390, y: 95, width: 590, height: 900)
        guard let cropped = cg.cropping(to: rect) else { return source }
        return NSImage(cgImage: cropped, size: rect.size)
    }

    private var points: [(Int, CGFloat, CGFloat)] {
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
                    if model == "g502x" {
                        if #available(macOS 26.0, *) {
                            GlassEffectContainer(spacing: 6) { hotspots(width: width, height: height) }
                        } else { hotspots(width: width, height: height) }
                    }
                }.frame(width: width, height: height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            } else {
                Image(systemName: "computermouse").font(.system(size: 150, weight: .ultraLight))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func hotspots(width: CGFloat, height: CGFloat) -> some View {
        ZStack {
            ForEach(points, id: \.0) { point in
                Button { selected = point.0 } label: {
                    hotspot(selected: selected == point.0)
                }.buttonStyle(.plain)
                    .accessibilityLabel(NSLocalizedString(["Left click","Right click","Middle click","Back","DPI shift","Forward","Tilt left","Tilt right","Profile cycle","DPI +","DPI -"][point.0], tableName: "MouseControl", comment: "Mouse button"))
                    .accessibilityAddTraits(selected == point.0 ? .isSelected : [])
                    .position(x: width * point.1, y: height * point.2)
            }
        }.frame(width: width, height: height)
    }

    @ViewBuilder private func hotspot(selected: Bool) -> some View {
        let dot = Circle().fill(selected ? Color.accentColor : Color.primary.opacity(0.65))
            .frame(width: 7, height: 7).frame(width: 28, height: 28)
        if #available(macOS 26.0, *) {
            dot.glassEffect(.regular.interactive(), in: Circle())
        } else {
            dot.background(.ultraThinMaterial, in: Circle())
        }
    }
}
