import Foundation

struct WiFiInfo: Codable, Equatable {
    var interface: String
    var poweredOn: Bool
    /// nil when Wi-Fi is off, not joined, or macOS is hiding the name (no Location permission).
    var ssid: String?
    /// True when the name is probably hidden because Location permission is missing.
    var ssidHidden: Bool
}

struct NetworkInfo: Codable, Equatable {
    var primaryInterface: String?
    var localIPs: [String]
    var router: String?
    var dnsServers: [String]

    static let empty = NetworkInfo(primaryInterface: nil, localIPs: [], router: nil, dnsServers: [])
}

struct TailscaleInfo: Codable, Equatable {
    var installed: Bool
    /// BackendState == "Running".
    var running: Bool
    var backendState: String?
    var ips: [String]
    /// Host name of the exit node in use, nil when none.
    var exitNode: String?
    var error: String?

    static let notInstalled = TailscaleInfo(installed: false, running: false, backendState: nil,
                                            ips: [], exitNode: nil, error: nil)
}

struct VPNService: Codable, Equatable, Identifiable {
    /// Service ID from `scutil --nc list` (a UUID).
    var id: String
    var name: String
    var provider: String?
    /// Connected, Disconnected, Connecting, Disconnecting, Invalid.
    var status: String

    var isConnected: Bool { status == "Connected" }
    var isBusy: Bool { status == "Connecting" || status == "Disconnecting" }
}

struct Connection: Codable, Equatable, Hashable, Identifiable {
    var command: String
    var pid: Int
    var fd: String
    /// IPv4 or IPv6.
    var family: String
    /// TCP or UDP.
    var proto: String
    var local: String
    var remote: String?
    /// TCP state (ESTABLISHED, LISTEN, ...); nil for UDP.
    var state: String?

    var id: String { "\(pid)-\(fd)-\(local)-\(remote ?? "")" }

    /// The widget's top N: established connections with a remote end first, then listeners,
    /// then the rest; alphabetical by process within each group.
    static func top(_ all: [Connection], limit: Int) -> [Connection] {
        func rank(_ c: Connection) -> Int {
            if c.state == "ESTABLISHED" && c.remote != nil { return 0 }
            if c.state == "LISTEN" { return 1 }
            return 2
        }
        let sorted = all.sorted {
            let (a, b) = (rank($0), rank($1))
            if a != b { return a < b }
            if $0.command != $1.command {
                return $0.command.localizedCaseInsensitiveCompare($1.command) == .orderedAscending
            }
            return $0.pid < $1.pid
        }
        return Array(sorted.prefix(limit))
    }
}

enum HelperState: String, Codable {
    case notInstalled, needsApproval, ready, error
}

/// Everything the widget shows. The app overwrites one file with this; nothing else is stored.
struct Snapshot: Codable, Equatable {
    var updated: Date
    var wifi: WiFiInfo?
    var network: NetworkInfo
    var tailscale: TailscaleInfo
    var vpns: [VPNService]
    var topConnections: [Connection]
    /// Total connections in the last helper read; nil when the helper isn't available.
    var connectionCount: Int?
    var helper: HelperState
    /// Last toggle error, shown until the next successful toggle.
    var message: String?

    /// Same content, ignoring the timestamp. Used to skip widget reloads when nothing changed.
    func sameContent(as other: Snapshot) -> Bool {
        var a = self, b = other
        a.updated = .distantPast
        b.updated = .distantPast
        return a == b
    }
}
