import AppKit
import Combine
import ServiceManagement
import WidgetKit

/// Owns the app's state: gathers status, runs toggles, keeps snapshot.json and the widget current.
@MainActor
final class Controller: ObservableObject {
    @Published private(set) var snapshot: Snapshot
    /// Full connection list. In memory only, never written to disk.
    @Published private(set) var allConnections: [Connection] = []
    @Published private(set) var busy = false
    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled

    let location = LocationPermission()
    private let helper = HelperClient()
    private var monitor: NetworkChangeMonitor?
    private var requestObserver: DarwinObserver?
    private var statusTimer: Timer?
    private var connectionTimer: Timer?
    private var debounce: DispatchWorkItem?
    private var refreshing = false
    private var refreshQueued = false
    private var queuedWantsConnections = false
    /// Number of open views showing live connections (menu, connections window).
    private var liveViewers = 0
    private var lastMessage: String?

    init() {
        snapshot = Snapshot(updated: Date(), wifi: nil, network: .empty, tailscale: .notInstalled, vpns: [],
                            topConnections: [], connectionCount: nil, helper: .notInstalled, message: nil)
        location.onChange = { [weak self] in Task { @MainActor in self?.refresh(connections: false) } }
        monitor = NetworkChangeMonitor { [weak self] in
            Task { @MainActor in self?.networkChanged() }
        }
        requestObserver = DarwinObserver(name: NW.requestNotification) { [weak self] in
            Task { @MainActor in self?.handleQueuedRequests() }
        }
        // Tailscale and VPN status don't always raise a network event; check them once a minute.
        statusTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(connections: false) }
        }
        statusTimer?.tolerance = 15
        scheduleConnectionTimer()
        NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
                                               object: nil, queue: .main) { _ in
            // Leave nothing behind: the widget falls back to "Open NetWidget".
            SnapshotStore.delete()
            WidgetCenter.shared.reloadAllTimelines()
        }
        if location.isUndecided { location.request() }
        handleQueuedRequests()
        refresh(connections: true)
    }

    // MARK: Refresh

    private func networkChanged() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.refresh(connections: false) }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: work)
    }

    /// Every 3 seconds while the connection list is on screen, otherwise every 5 minutes.
    private func scheduleConnectionTimer() {
        connectionTimer?.invalidate()
        let live = liveViewers > 0
        connectionTimer = Timer.scheduledTimer(withTimeInterval: live ? 3 : 300, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh(connections: true) }
        }
        connectionTimer?.tolerance = live ? 0.5 : 60
    }

    func setLiveView(_ visible: Bool) {
        liveViewers = max(0, liveViewers + (visible ? 1 : -1))
        scheduleConnectionTimer()
        if visible { refresh(connections: true) }
    }

    func refresh(connections wantConnections: Bool) {
        if refreshing {
            refreshQueued = true
            queuedWantsConnections = queuedWantsConnections || wantConnections
            return
        }
        refreshing = true
        let locationOK = location.isAuthorized
        let helperState = helper.state
        let helper = self.helper

        Task {
            let gathered = await Task.detached(priority: .utility) { () -> (WiFiInfo?, NetworkInfo, TailscaleInfo, [VPNService]) in
                (WiFiReader.read(locationAuthorized: locationOK), NetworkReader.read(),
                 StatusReaders.tailscale(), StatusReaders.vpns())
            }.value

            var connections: [Connection]?
            var helperResult = helperState
            if wantConnections && helperState == .ready {
                do {
                    connections = try await helper.listConnections()
                    if self.lastMessage?.hasPrefix("Helper:") == true { self.lastMessage = nil }
                }
                catch { helperResult = .error; self.lastMessage = "Helper: \(error.localizedDescription)" }
            }
            self.apply(gathered, connections: connections, helper: helperResult)
            self.refreshing = false
            if self.refreshQueued {
                let want = self.queuedWantsConnections
                self.refreshQueued = false
                self.queuedWantsConnections = false
                self.refresh(connections: want)
            }
        }
    }

    private func apply(_ g: (WiFiInfo?, NetworkInfo, TailscaleInfo, [VPNService]),
                       connections: [Connection]?, helper: HelperState) {
        var next = snapshot
        next.updated = Date()
        next.wifi = g.0
        next.network = g.1
        next.tailscale = g.2
        next.vpns = g.3
        next.helper = helper
        next.message = lastMessage
        if let connections {
            allConnections = connections
            next.topConnections = Connection.top(connections, limit: NW.widgetConnectionLimit)
            next.connectionCount = connections.count
        } else if helper != .ready {
            allConnections = []
            next.topConnections = []
            next.connectionCount = nil
        }
        let changed = !next.sameContent(as: snapshot)
        snapshot = next
        if changed || SnapshotStore.read() == nil {
            try? SnapshotStore.write(next)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    // MARK: Toggles

    private func handleQueuedRequests() {
        for request in RequestChannel.consume() { perform(request) }
    }

    func perform(_ request: ToggleRequest) {
        if case .wifi(on: false) = request, let wifi = snapshot.wifi,
           snapshot.network.primaryInterface == wifi.interface, !confirmWiFiOff() {
            return
        }
        busy = true
        Task {
            let error = await Task.detached(priority: .userInitiated) { Self.execute(request) }.value
            self.lastMessage = error
            self.busy = false
            self.refresh(connections: false)
        }
    }

    /// Validates against fresh system state and runs one command. Returns an error message or nil.
    nonisolated private static func execute(_ request: ToggleRequest) -> String? {
        var context = CommandContext()
        let command: AllowedCommand
        switch request {
        case .wifi(let on):
            guard let iface = WiFiReader.read(locationAuthorized: false)?.interface else {
                return "No Wi-Fi interface found."
            }
            context.wifiInterfaces = WiFiReader.interfaceNames()
            command = .wifiPower(interface: iface, on: on)
        case .tailscale(let up):
            command = up ? .tailscaleUp : .tailscaleDown
        case .exitNode(let on):
            command = on ? .exitNodeOn : .exitNodeOff
        case let .vpn(id, connect):
            context.vpnIDs = Set(StatusReaders.vpns().map(\.id))
            command = connect ? .vpnStart(id: id) : .vpnStop(id: id)
        }
        do {
            let result = try command.run(in: context, timeout: 15)
            if result.timedOut { return "\(label(request)) timed out." }
            if result.status != 0 {
                return "\(label(request)) failed: " +
                    (StatusReaders.firstLine(result.stderr) ?? StatusReaders.firstLine(result.stdout) ?? "exit \(result.status)")
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    nonisolated private static func label(_ r: ToggleRequest) -> String {
        switch r {
        case .wifi(let on): return on ? "Wi-Fi on" : "Wi-Fi off"
        case .tailscale(let up): return up ? "Tailscale up" : "Tailscale down"
        case .exitNode(let on): return on ? "Exit node on" : "Exit node off"
        case .vpn(_, let c): return c ? "VPN connect" : "VPN disconnect"
        }
    }

    /// Wi-Fi is carrying this Mac's internet connection; turning it off would cut it.
    private func confirmWiFiOff() -> Bool {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Turn off Wi-Fi?"
        alert.informativeText = "Wi-Fi is this Mac's main internet connection. Turning it off will disconnect it, including Tailscale and any VPN."
        alert.addButton(withTitle: "Turn Off")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    // MARK: Helper, login item, location

    func installHelper() {
        do { try helper.install(); lastMessage = nil }
        catch { lastMessage = "Helper install: \(error.localizedDescription)" }
        refresh(connections: true)
    }

    func uninstallHelper() {
        Task {
            do { try await helper.uninstall(); lastMessage = nil }
            catch { lastMessage = "Helper removal: \(error.localizedDescription)" }
            refresh(connections: true)
        }
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            lastMessage = "Launch at login: \(error.localizedDescription)"
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func openLocationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices") {
            NSWorkspace.shared.open(url)
        }
    }
}
