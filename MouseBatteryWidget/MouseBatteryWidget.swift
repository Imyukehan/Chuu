import SwiftUI
import WidgetKit
import OSLog

struct BatteryEntry: TimelineEntry {
    let date: Date
    let snapshot: MouseSnapshotFile?
}

struct BatteryProvider: TimelineProvider {
    func placeholder(in context: Context) -> BatteryEntry {
        BatteryEntry(date: Date(), snapshot: MouseSnapshotFile(devices: [
            MouseSnapshot(id: "preview", model: "g502x", name: "G502 X PLUS", battery: 83,
                          charging: false, online: true, updatedAt: Date())
        ], writtenAt: Date()))
    }
    func getSnapshot(in context: Context, completion: @escaping (BatteryEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : BatteryEntry(date: Date(), snapshot: MouseSnapshotStore.read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<BatteryEntry>) -> Void) {
        let now = Date()
        let snapshot = MouseSnapshotStore.read()
        Logger(subsystem: "moe.khan.MouseControl", category: "Widgets")
            .info("Battery timeline: \(snapshot?.devices.count ?? 0) devices, first reading \(snapshot?.devices.first?.battery ?? -1) percent")
        let expiry = max(now.addingTimeInterval(1), (snapshot?.writtenAt ?? now).addingTimeInterval(30 * 60))
        completion(Timeline(entries: [BatteryEntry(date: now, snapshot: snapshot), BatteryEntry(date: expiry, snapshot: snapshot)],
                            policy: .after(now.addingTimeInterval(15 * 60))))
    }
}

struct MouseBatteryView: View {
    @Environment(\.widgetFamily) var family
    let entry: BatteryEntry
    private var devices: [MouseSnapshot] { entry.snapshot?.devices ?? [] }

    var body: some View {
        Group {
            if devices.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "computermouse").font(.largeTitle).foregroundStyle(.secondary)
                    Text(NSLocalizedString("No mouse connected", tableName: "MouseControl", comment: "Widget empty state")).font(.caption)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if family == .systemMedium && devices.count > 1 {
                HStack(spacing: 20) { ForEach(Array(devices.prefix(2))) { device in tile(device) } }
            } else {
                tile(devices[0])
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(URL(string: "mousecontrol://devices"))
    }

    private func tile(_ device: MouseSnapshot) -> some View {
        let fresh = device.isFresh(at: entry.date)
        return VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: "computermouse.fill").font(.title3)
                Spacer()
                Image(systemName: device.charging ? "bolt.fill" : "antenna.radiowaves.left.and.right")
                    .foregroundStyle(device.online && fresh ? .green : .secondary)
            }
            Spacer(minLength: 0)
            Text(device.battery.map { "\($0)%" } ?? "—")
                .font(.system(size: 32, weight: .medium, design: .rounded)).monospacedDigit()
            Text(device.name).font(.caption.weight(.medium)).lineLimit(1).minimumScaleFactor(0.8)
            HStack(spacing: 4) {
                Text(device.battery == nil ? NSLocalizedString("Battery unavailable", tableName: "MouseControl", comment: "Widget state") :
                    fresh && device.online ? device.connectionLabel : NSLocalizedString("Last seen", tableName: "MouseControl", comment: "Widget stale state"))
                if device.battery != nil && (!fresh || !device.online) { Text(device.updatedAt, style: .time) }
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

@main
struct MouseBatteryWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: MouseSnapshotStore.widgetKind, provider: BatteryProvider()) { MouseBatteryView(entry: $0) }
            .configurationDisplayName("Chuu")
            .description(NSLocalizedString("Mouse battery", tableName: "MouseControl", comment: "Widget gallery description"))
            .supportedFamilies([.systemSmall, .systemMedium])
    }
}
