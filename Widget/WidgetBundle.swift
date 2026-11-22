import SwiftUI
import WidgetKit

@main
struct NetWidgetBundle: WidgetBundle {
    var body: some Widget { NetworkWidget() }
}

struct NetworkWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NetworkWidget", provider: Provider()) { entry in
            WidgetRootView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Network")
        .description("Wi-Fi, Tailscale, VPN toggles and connection status.")
        .supportedFamilies([.systemMedium, .systemLarge])
    }
}

struct Entry: TimelineEntry {
    let date: Date
    let snapshot: Snapshot?
}

/// Reads the snapshot the app wrote. Never schedules its own refreshes (.never): the app
/// reloads the widget only when the snapshot changes, which keeps battery use near zero.
struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: Date(), snapshot: .preview) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        completion(Entry(date: Date(), snapshot: context.isPreview ? (SnapshotStore.read() ?? .preview) : SnapshotStore.read()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        completion(Timeline(entries: [Entry(date: Date(), snapshot: SnapshotStore.read())], policy: .never))
    }
}

extension Snapshot {
    /// Sample data for the widget gallery. Documentation-range addresses only.
    static let preview = Snapshot(
        updated: Date(),
        wifi: WiFiInfo(interface: "en0", poweredOn: true, ssid: "Example Network", ssidHidden: false),
        network: NetworkInfo(primaryInterface: "en0", localIPs: ["192.0.2.10"], router: "192.0.2.1",
                             dnsServers: ["192.0.2.1"]),
        tailscale: TailscaleInfo(installed: true, running: true, backendState: "Running",
                                 ips: ["100.64.0.10"], exitNode: nil, error: nil),
        vpns: [VPNService(id: "00000000-0000-0000-0000-000000000000", name: "Example VPN",
                          provider: nil, status: "Disconnected")],
        topConnections: [
            Connection(command: "Safari", pid: 101, fd: "20", family: "IPv4", proto: "TCP",
                       local: "192.0.2.10:50000", remote: "198.51.100.5:443", state: "ESTABLISHED"),
        ],
        connectionCount: 1, helper: .ready, message: nil)
}
