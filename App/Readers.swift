import Foundation
import CoreWLAN
import CoreLocation
import SystemConfiguration

// Read-only status sources. Everything except Tailscale and VPN status uses Apple frameworks
// directly; those two go through the fixed command list.

enum WiFiReader {
    static func interfaceNames() -> Set<String> {
        Set(CWWiFiClient.shared().interfaceNames() ?? [])
    }

    /// nil when the Mac has no Wi-Fi hardware.
    static func read(locationAuthorized: Bool) -> WiFiInfo? {
        guard let iface = CWWiFiClient.shared().interface(), let name = iface.interfaceName else { return nil }
        let on = iface.powerOn()
        let ssid = iface.ssid()
        // macOS returns no name without Location permission even when joined.
        let joined = iface.wlanChannel() != nil
        return WiFiInfo(interface: name, poweredOn: on, ssid: ssid,
                        ssidHidden: on && joined && ssid == nil && !locationAuthorized)
    }
}

enum NetworkReader {
    static func read() -> NetworkInfo {
        guard let store = SCDynamicStoreCreate(nil, "NetWidget" as CFString, nil, nil) else { return .empty }
        let ipv4 = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any]
        let dns = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any]
        let primary = ipv4?["PrimaryInterface"] as? String
        return NetworkInfo(
            primaryInterface: primary,
            localIPs: primary.map(addresses(for:)) ?? [],
            router: ipv4?["Router"] as? String,
            dnsServers: dns?["ServerAddresses"] as? [String] ?? [])
    }

    /// IPv4 and non-link-local IPv6 addresses on one interface.
    static func addresses(for interface: String) -> [String] {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return [] }
        defer { freeifaddrs(head) }
        var v4: [String] = [], v6: [String] = []
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard String(cString: ifa.ifa_name) == interface, let addr = ifa.ifa_addr else { continue }
            let family = Int32(addr.pointee.sa_family)
            guard family == AF_INET || family == AF_INET6 else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count),
                              nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let text = String(cString: host)
            if family == AF_INET { v4.append(text) }
            else if !text.lowercased().hasPrefix("fe80") { v6.append(text) }
        }
        return v4 + v6
    }
}

enum StatusReaders {
    /// Detected from the network interfaces, never by running Tailscale's binary: that binary is the
    /// Tailscale app itself, so every `status` call launched it (and the menu bar icon flickered).
    /// Tailscale is "up" when a tunnel interface holds an address in 100.64.0.0/10.
    static func tailscale() -> TailscaleInfo {
        guard FileManager.default.isExecutableFile(atPath: NW.tailscaleBinary) else { return .notInstalled }
        let found = tunnelAddresses()
        let running = !found.ips.isEmpty
        // With an exit node, the default route goes through Tailscale's tunnel.
        let primary = NetworkReader.read().primaryInterface
        let viaTunnel = running && primary != nil && found.interfaces.contains(primary!)
        return TailscaleInfo(installed: true, running: running, backendState: running ? "Running" : "Stopped",
                             ips: found.ips, exitNode: viaTunnel ? NW.exitNodeName : nil, error: nil)
    }

    static func tunnelAddresses() -> (ips: [String], interfaces: Set<String>) {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let first = head else { return ([], []) }
        defer { freeifaddrs(head) }
        var ips: [String] = [], names = Set<String>()
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            let name = String(cString: ifa.ifa_name)
            guard name.hasPrefix("utun"), let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let v4 = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            // 100.64.0.0/10
            guard v4 & 0xFFC0_0000 == 0x6440_0000 else { continue }
            var a = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            var buf = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
            inet_ntop(AF_INET, &a, &buf, socklen_t(buf.count))
            ips.append(String(cString: buf)); names.insert(name)
        }
        return (ips, names)
    }

    static func vpns() -> [VPNService] {
        guard let r = try? AllowedCommand.vpnList.run(), r.status == 0 else { return [] }
        return VPNListParser.parse(r.stdout)
    }

    static func firstLine(_ s: String) -> String? {
        let line = s.split(separator: "\n").first.map { String($0.prefix(200)) }
        return line?.isEmpty == false ? line : nil
    }
}

/// Calls back on the main thread when IP, router, DNS, Wi-Fi association or VPN/Tailscale
/// tunnels change. Event-driven: macOS pushes these, nothing polls.
final class NetworkChangeMonitor {
    private var store: SCDynamicStore?
    private var source: CFRunLoopSource?
    private let onChange: () -> Void

    init(onChange: @escaping () -> Void) {
        self.onChange = onChange
        var context = SCDynamicStoreContext(version: 0, info: Unmanaged.passUnretained(self).toOpaque(),
                                            retain: nil, release: nil, copyDescription: nil)
        store = SCDynamicStoreCreate(nil, "NetWidget.monitor" as CFString, { _, _, info in
            guard let info else { return }
            Unmanaged<NetworkChangeMonitor>.fromOpaque(info).takeUnretainedValue().onChange()
        }, &context)
        guard let store else { return }
        let patterns = [
            "State:/Network/Global/.*",
            "State:/Network/Interface/.*/(IPv4|IPv6|AirPort|Link)",
            "State:/Network/Service/.*/IPv4",
        ] as CFArray
        SCDynamicStoreSetNotificationKeys(store, nil, patterns)
        source = SCDynamicStoreCreateRunLoopSource(nil, store, 0)
        if let source { CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes) }
    }

    deinit {
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
    }
}

/// Listens for the widget's Darwin notification.
final class DarwinObserver {
    private let handler: () -> Void

    init(name: String, handler: @escaping () -> Void) {
        self.handler = handler
        CFNotificationCenterAddObserver(
            CFNotificationCenterGetDarwinNotifyCenter(), Unmanaged.passUnretained(self).toOpaque(),
            { _, observer, _, _, _ in
                guard let observer else { return }
                let me = Unmanaged<DarwinObserver>.fromOpaque(observer).takeUnretainedValue()
                DispatchQueue.main.async { me.handler() }
            },
            name as CFString, nil, .deliverImmediately)
    }

    deinit {
        CFNotificationCenterRemoveEveryObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                                Unmanaged.passUnretained(self).toOpaque())
    }
}

/// Location permission, which macOS requires before CoreWLAN reveals the Wi-Fi name.
final class LocationPermission: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    var onChange: (() -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }
    var isAuthorized: Bool { status == .authorizedAlways }
    var isUndecided: Bool { status == .notDetermined }

    func request() { manager.requestWhenInUseAuthorization() }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) { onChange?() }
}
