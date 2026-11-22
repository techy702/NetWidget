import AppIntents
import SwiftUI
import WidgetKit

struct WidgetRootView: View {
    let entry: Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        if let s = entry.snapshot {
            VStack(alignment: .leading, spacing: 8) {
                ToggleRow(s: s)
                StatusLines(s: s)
                if family == .systemLarge {
                    Divider()
                    LargeDetails(s: s)
                }
                Spacer(minLength: 0)
            }
        } else {
            VStack(spacing: 6) {
                Image(systemName: "network").font(.title)
                Text("Open NetWidget").font(.headline)
                Text("The menu bar app supplies this widget's data and runs its buttons.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
    }
}

/// Four buttons: Wi-Fi, Tailscale, exit node, first VPN. Each sends the opposite of the current state.
private struct ToggleRow: View {
    let s: Snapshot

    var body: some View {
        HStack(spacing: 6) {
            let wifiOn = s.wifi?.poweredOn ?? false
            Button(intent: ToggleWiFiIntent(turnOn: !wifiOn)) {
                Tile(title: "Wi-Fi", icon: wifiOn ? "wifi" : "wifi.slash", on: wifiOn)
            }
            .disabled(s.wifi == nil)

            let tsOn = s.tailscale.running
            Button(intent: ToggleTailscaleIntent(up: !tsOn)) {
                Tile(title: "Tailscale", icon: "point.3.connected.trianglepath.dotted", on: tsOn)
            }
            .disabled(!s.tailscale.installed)

            let exitOn = s.tailscale.exitNode != nil
            Button(intent: ToggleExitNodeIntent(turnOn: !exitOn)) {
                Tile(title: "Exit \(NW.exitNodeName)", icon: "arrow.up.forward.circle", on: exitOn)
            }
            .disabled(!tsOn)

            if let vpn = s.vpns.first {
                Button(intent: ToggleVPNIntent(serviceID: vpn.id, connect: !vpn.isConnected)) {
                    Tile(title: vpn.name, icon: "lock.shield", on: vpn.isConnected)
                }
                .disabled(vpn.isBusy)
            } else {
                Tile(title: "No VPN", icon: "lock.slash", on: false).opacity(0.4)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct Tile: View {
    let title: String
    let icon: String
    let on: Bool

    var body: some View {
        VStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 15, weight: .semibold))
            Text(title).font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, minHeight: 40)
        .foregroundStyle(on ? Color.white : Color.primary)
        .background(on ? Color.accentColor : Color.secondary.opacity(0.18),
                    in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct StatusLines: View {
    let s: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            line("wifi", wifiText)
            line("number", "\(s.network.localIPs.first ?? "No IP")  \(s.network.primaryInterface ?? "")")
            line("point.3.connected.trianglepath.dotted", tailscaleText)
        }
        .font(.system(size: 11))
    }

    private var wifiText: String {
        guard let w = s.wifi else { return "No Wi-Fi" }
        if !w.poweredOn { return "Wi-Fi off (\(w.interface))" }
        return "\(w.ssid ?? (w.ssidHidden ? "Name hidden" : "Not joined"))  \(w.interface)"
    }

    private var tailscaleText: String {
        let ts = s.tailscale
        guard ts.installed else { return "Tailscale not installed" }
        guard ts.running else { return "Tailscale \(ts.backendState ?? "off")" }
        return "\(ts.ips.first ?? "")  exit: \(ts.exitNode ?? "none")"
    }
}

private struct LargeDetails: View {
    let s: Snapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            line("arrow.triangle.branch", "Router \(s.network.router ?? "none")")
            line("server.rack", "DNS \(s.network.dnsServers.prefix(2).joined(separator: ", "))")
            ForEach(s.vpns) { vpn in line("lock.shield", "\(vpn.name): \(vpn.status)") }
            if let m = s.message {
                Text(m).font(.system(size: 10)).foregroundStyle(.orange).lineLimit(2)
            }
            Divider()
            connections
        }
        .font(.system(size: 11))
    }

    @ViewBuilder private var connections: some View {
        switch s.helper {
        case .ready:
            Text("Connections (\(s.connectionCount ?? 0))").font(.system(size: 11, weight: .semibold))
            ForEach(s.topConnections) { c in
                HStack(spacing: 4) {
                    Text(c.command).frame(width: 78, alignment: .leading)
                    Text(c.remote ?? c.local).truncationMode(.middle)
                    Spacer(minLength: 2)
                    Text(c.state.map(short) ?? c.proto).foregroundStyle(.secondary)
                }
                .font(.system(size: 9.5, design: .monospaced))
                .lineLimit(1)
            }
        default:
            Text("Install the helper from the menu bar app to list connections.")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }

    private func short(_ state: String) -> String {
        switch state {
        case "ESTABLISHED": return "EST"
        case "LISTEN": return "LSN"
        default: return String(state.prefix(4))
        }
    }
}

private func line(_ icon: String, _ text: String) -> some View {
    HStack(spacing: 5) {
        Image(systemName: icon).frame(width: 14).foregroundStyle(.secondary)
        Text(text).lineLimit(1).truncationMode(.middle)
    }
}
