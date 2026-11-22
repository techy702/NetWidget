import SwiftUI

struct MenuView: View {
    @EnvironmentObject private var c: Controller
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let s = c.snapshot
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("NetWidget").font(.headline)
                Spacer()
                if c.busy { ProgressView().controlSize(.small) }
                Text(s.updated, style: .time).font(.caption).foregroundStyle(.secondary)
            }

            if let message = s.message {
                Text(message).font(.caption).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            }

            wifiSection(s)
            Divider()
            tailscaleSection(s)
            Divider()
            vpnSection(s)
            Divider()
            connectionsSection(s)
            Divider()

            Toggle("Launch at login", isOn: Binding(get: { c.launchAtLogin }, set: { c.setLaunchAtLogin($0) }))
            HStack {
                Button("Refresh") { c.refresh(connections: true) }
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 340)
        .onAppear { c.setLiveView(true) }
        .onDisappear { c.setLiveView(false) }
    }

    @ViewBuilder private func wifiSection(_ s: Snapshot) -> some View {
        if let wifi = s.wifi {
            Toggle(isOn: Binding(get: { wifi.poweredOn }, set: { c.perform(.wifi(on: $0)) })) {
                Label("Wi-Fi (\(wifi.interface))", systemImage: wifi.poweredOn ? "wifi" : "wifi.slash")
            }
            .toggleStyle(.switch)
            if wifi.poweredOn {
                row("Network", wifi.ssid ?? (wifi.ssidHidden ? "Hidden (needs Location)" : "Not joined"))
                if wifi.ssidHidden {
                    Button(c.location.isUndecided ? "Allow Location to show the Wi-Fi name" : "Open Location settings") {
                        if c.location.isUndecided { c.location.request() } else { c.openLocationSettings() }
                    }
                    .font(.caption)
                }
            }
        } else {
            row("Wi-Fi", "No Wi-Fi hardware")
        }
        row("Primary", s.network.primaryInterface ?? "None")
        row("IP", s.network.localIPs.first ?? "None")
        row("Router", s.network.router ?? "None")
        row("DNS", s.network.dnsServers.isEmpty ? "None" : s.network.dnsServers.joined(separator: ", "))
    }

    @ViewBuilder private func tailscaleSection(_ s: Snapshot) -> some View {
        let ts = s.tailscale
        if ts.installed {
            Toggle(isOn: Binding(get: { ts.running }, set: { c.perform(.tailscale(up: $0)) })) {
                Label("Tailscale", systemImage: "point.3.connected.trianglepath.dotted")
            }
            .toggleStyle(.switch)
            Toggle(isOn: Binding(get: { ts.exitNode != nil }, set: { c.perform(.exitNode(on: $0)) })) {
                Label("Exit node \(NW.exitNodeName)", systemImage: "arrow.up.forward.circle")
            }
            .toggleStyle(.switch)
            .disabled(!ts.running)
            row("State", ts.backendState ?? "Unknown")
            row("Tailnet IP", ts.ips.first ?? "None")
            row("Exit node", ts.exitNode ?? "None")
            if let e = ts.error { Text(e).font(.caption).foregroundStyle(.orange) }
        } else {
            row("Tailscale", "Not installed")
        }
    }

    @ViewBuilder private func vpnSection(_ s: Snapshot) -> some View {
        if s.vpns.isEmpty {
            row("VPN", "No VPN profiles")
        } else {
            ForEach(s.vpns) { vpn in
                Toggle(isOn: Binding(get: { vpn.isConnected }, set: { c.perform(.vpn(id: vpn.id, connect: $0)) })) {
                    Label("\(vpn.name) (\(vpn.status))", systemImage: "lock.shield")
                }
                .toggleStyle(.switch)
                .disabled(vpn.isBusy)
            }
        }
    }

    @ViewBuilder private func connectionsSection(_ s: Snapshot) -> some View {
        switch s.helper {
        case .ready:
            HStack {
                Text("Connections: \(s.connectionCount.map(String.init) ?? "...")")
                Spacer()
                Button("Show all") {
                    openWindow(id: "connections")
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            ForEach(s.topConnections.prefix(5)) { conn in
                Text("\(conn.command)  \(conn.remote ?? conn.local)  \(conn.state ?? conn.proto)")
                    .font(.caption.monospaced()).lineLimit(1).truncationMode(.middle)
            }
            Button("Remove helper") { c.uninstallHelper() }.font(.caption)
        case .needsApproval:
            Text("Helper waiting for approval in System Settings > General > Login Items.").font(.caption)
            Button("Open Login Items") { c.installHelper() }
        case .notInstalled:
            Text("Connections for all processes need the helper (one-time approval).").font(.caption)
            Button("Install helper") { c.installHelper() }
        case .error:
            Text("Helper not responding.").font(.caption).foregroundStyle(.orange)
            HStack {
                Button("Retry") { c.refresh(connections: true) }
                Button("Remove helper") { c.uninstallHelper() }
            }
        }
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(title).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
            Text(value).textSelection(.enabled).lineLimit(2)
        }
        .font(.caption)
    }
}
