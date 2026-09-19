import AppKit
import Combine
import WidgetKit
import OSLog

@available(macOS 14.0, *)
final class ChuuModel: ObservableObject {
    static let shared = ChuuModel()
    @Published private(set) var devices: [MouseSnapshot] = []
    @Published var selectedID: String? { didSet { if selectedID != oldValue { loadProfile() } } }
    @Published private(set) var profile: OnboardMouseProfile?
    @Published private(set) var busy = false
    @Published private(set) var scanning = false
    @Published var error: String?
    @Published private(set) var profileError: String?
    private let queue = DispatchQueue(label: "moe.khan.MouseControl.hardware", qos: .utility)
    private var timer: Timer?
    private var sleeping = false
    private var watcher: MouseConnectionWatcher?
    private var hotPlugRefresh: DispatchWorkItem?

    var selected: MouseSnapshot? { devices.first { $0.id == selectedID } }

    func start() {
        guard timer == nil else { refresh(); return }
        watcher = MouseConnectionWatcher()
        watcher?.onChange = { [weak self] id, connected in
            guard let self else { return }
            if !connected { MouseAlerts.shared.deviceRemoved(id) }
            self.hotPlugRefresh?.cancel()
            let work = DispatchWorkItem { [weak self] in self?.refresh() }
            self.hotPlugRefresh = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
        }
        WidgetCenter.shared.getCurrentConfigurations { result in
            let log = OSLog(subsystem: "moe.khan.MouseControl", category: "Widgets")
            switch result {
            case .success(let widgets):
                os_log("Configured battery widgets: %d", log: log, type: .info,
                       widgets.filter { $0.kind == MouseSnapshotStore.widgetKind }.count)
            case .failure(let error):
                os_log("Widget configuration query failed: %{public}@", log: log, type: .error, error.localizedDescription)
            }
        }
        refresh()
        let timer = Timer(timeInterval: 30, repeats: true) { [weak self] _ in self?.refresh() }
        timer.tolerance = 3
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(wake), name: NSWorkspace.didWakeNotification, object: nil)
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(sleep), name: NSWorkspace.willSleepNotification, object: nil)
    }

    @objc private func sleep() { sleeping = true; MouseAlerts.shared.suspend() }
    @objc private func wake() { sleeping = false; MouseAlerts.shared.resume(); refresh() }

    func refresh() {
        guard !scanning, !busy, !sleeping else { return }
        scanning = true
        queue.async {
            let result = Result { try MouseHardwareService.scan() }
            DispatchQueue.main.async {
                self.scanning = false
                switch result {
                case .success(let readings):
                    let devices = readings.map { reading -> MouseSnapshot in
                        guard !reading.online, let previous = self.devices.first(where: { $0.id == reading.id }),
                              previous.battery != nil else { return reading }
                        var cached = reading
                        cached.battery = previous.battery
                        cached.updatedAt = previous.updatedAt
                        return cached
                    }
                    let changed = self.devices.map { "\($0.id):\($0.battery ?? -1):\($0.online):\($0.charging)" } !=
                        devices.map { "\($0.id):\($0.battery ?? -1):\($0.online):\($0.charging)" }
                    self.devices = devices
                    MouseAlerts.shared.update(devices)
                    if !devices.contains(where: { $0.id == self.selectedID }) { self.selectedID = devices.first?.id }
                    if self.selected?.online != true { self.profile = nil }
                    else if self.profile == nil && self.profileError == nil { self.loadProfile() }
                    do {
                        try MouseSnapshotStore.write(devices)
                        if changed { WidgetCenter.shared.reloadTimelines(ofKind: MouseSnapshotStore.widgetKind) }
                    } catch { self.error = error.localizedDescription }
                case .failure(let error):
                    self.error = error.localizedDescription
                    self.devices = []
                    self.profile = nil
                    try? MouseSnapshotStore.write([])
                    WidgetCenter.shared.reloadTimelines(ofKind: MouseSnapshotStore.widgetKind)
                }
            }
        }
    }

    func loadProfile() {
        profile = nil
        profileError = nil
        guard let device = selected, device.model == "g502x", device.online, !busy else { return }
        busy = true
        queue.async {
            let result = Result { try MouseHardwareService.profile(id: device.id) }
            DispatchQueue.main.async {
                self.busy = false
                guard self.selectedID == device.id else { self.loadProfile(); return }
                switch result {
                case .success(let profile): self.profile = profile
                case .failure(let error): self.profileError = error.localizedDescription
                }
            }
        }
    }

    func save(button: Int? = nil, mapping: [UInt8]? = nil, lightingEnabled: Bool? = nil) {
        guard let profile, !busy else { return }
        busy = true
        queue.async {
            let result = Result { try MouseHardwareService.save(profile, button: button, mapping: mapping, lightingEnabled: lightingEnabled) }
            DispatchQueue.main.async {
                self.busy = false
                guard self.selectedID == profile.deviceID else { self.loadProfile(); return }
                switch result {
                case .success(let updated): self.profile = updated
                case .failure(let error): self.error = error.localizedDescription; self.loadProfile()
                }
            }
        }
    }
}
