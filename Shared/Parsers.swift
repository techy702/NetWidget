import Foundation

/// Parses `lsof -i -n -P -F pcPtnT` output. Each line starts with a one-letter field tag:
/// p=PID, c=command, f=file descriptor, t=IPv4/IPv6, P=TCP/UDP, n=address, T=TCP info (ST=state).
enum LsofParser {
    static func parse(_ text: String) -> [Connection] {
        var result: [Connection] = []
        var pid = 0
        var command = ""
        var fd: String?
        var family = "", proto = "", name: String?, state: String?

        func flush() {
            if let fd, let name {
                let parts = name.components(separatedBy: "->")
                result.append(Connection(
                    command: command, pid: pid, fd: fd, family: family, proto: proto,
                    local: parts[0], remote: parts.count > 1 ? parts[1] : nil, state: state))
            }
            fd = nil; family = ""; proto = ""; name = nil; state = nil
        }

        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let tag = line.first else { continue }
            let value = String(line.dropFirst())
            switch tag {
            case "p": flush(); pid = Int(value) ?? 0; command = ""
            case "c": command = value
            case "f": flush(); fd = value
            case "t": family = value
            case "P": proto = value
            case "n": name = value
            case "T": if value.hasPrefix("ST=") { state = String(value.dropFirst(3)) }
            default: break
            }
        }
        flush()
        return result
    }
}

/// Parses `scutil --nc list`. Example line:
/// `* (Disconnected)   10AF9C69-AC94-4FBC-A9B1-02507F693499 VPN (ch.protonvpn.mac) "ProtonVPN"   [VPN:ch.protonvpn.mac]`
/// Tailscale also registers as a VPN service; it is left out because it has its own controls.
enum VPNListParser {
    private static let regex = try! NSRegularExpression(
        pattern: #"^\*?\s*\(([^)]+)\)\s+([0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12})\s+\S+(?:\s+\(([^)]*)\))?\s+"([^"]*)""#)

    static func parse(_ text: String) -> [VPNService] {
        text.split(separator: "\n").compactMap { sub in
            let line = String(sub)
            let ns = line as NSString
            guard let m = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
                return nil
            }
            func group(_ i: Int) -> String? {
                let r = m.range(at: i)
                return r.location == NSNotFound ? nil : ns.substring(with: r)
            }
            let service = VPNService(id: group(2)!, name: group(4)!, provider: group(3), status: group(1)!)
            return isTailscale(service) ? nil : service
        }
    }

    static func isTailscale(_ s: VPNService) -> Bool {
        (s.provider ?? "").lowercased().contains("tailscale") || s.name.lowercased() == "tailscale"
    }
}

/// Parses `tailscale status --json`, keeping only the fields the widget shows.
enum TailscaleParser {
    private struct Status: Decodable {
        let BackendState: String?
        let TailscaleIPs: [String]?
        let SelfNode: Peer?
        let Peer: [String: Peer]?
        enum CodingKeys: String, CodingKey {
            case BackendState, TailscaleIPs, Peer
            case SelfNode = "Self"
        }
    }
    private struct Peer: Decodable {
        let HostName: String?
        let DNSName: String?
        let TailscaleIPs: [String]?
        let ExitNode: Bool?
    }

    static func parse(_ json: String) -> TailscaleInfo? {
        guard let data = json.data(using: .utf8),
              let s = try? JSONDecoder().decode(Status.self, from: data) else { return nil }
        let exit = s.Peer?.values.first { $0.ExitNode == true }
        // Prefer the first DNS label ("v2" from "v2.taile5fe8f.ts.net."), which matches what
        // `tailscale set --exit-node=` takes; fall back to the host name.
        let exitName = exit.map { peer -> String in
            if let dns = peer.DNSName, let label = dns.split(separator: ".").first { return String(label) }
            return peer.HostName ?? "unknown"
        }
        return TailscaleInfo(
            installed: true,
            running: s.BackendState == "Running",
            backendState: s.BackendState,
            ips: s.TailscaleIPs ?? s.SelfNode?.TailscaleIPs ?? [],
            exitNode: exitName,
            error: nil)
    }
}
