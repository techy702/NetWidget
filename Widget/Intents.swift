import AppIntents
import WidgetKit

// Widget buttons. They run inside the sandboxed widget extension, so they can't run commands:
// each one queues a request with the desired end state and pings the menu bar app, which
// validates it against its fixed command list and does the work.

struct ToggleWiFiIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Wi-Fi"
    static var isDiscoverable = false
    @Parameter(title: "On", default: true) var turnOn: Bool

    init() {}
    init(turnOn: Bool) { self.turnOn = turnOn }

    func perform() async throws -> some IntentResult {
        RequestChannel.post(.wifi(on: turnOn))
        return .result()
    }
}

struct ToggleTailscaleIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Tailscale"
    static var isDiscoverable = false
    @Parameter(title: "Up", default: true) var up: Bool

    init() {}
    init(up: Bool) { self.up = up }

    func perform() async throws -> some IntentResult {
        RequestChannel.post(.tailscale(up: up))
        return .result()
    }
}

struct ToggleExitNodeIntent: AppIntent {
    static var title: LocalizedStringResource = "Set Exit Node"
    static var isDiscoverable = false
    @Parameter(title: "On", default: true) var turnOn: Bool

    init() {}
    init(turnOn: Bool) { self.turnOn = turnOn }

    func perform() async throws -> some IntentResult {
        RequestChannel.post(.exitNode(on: turnOn))
        return .result()
    }
}

struct ToggleVPNIntent: AppIntent {
    static var title: LocalizedStringResource = "Set VPN"
    static var isDiscoverable = false
    @Parameter(title: "Service ID", default: "") var serviceID: String
    @Parameter(title: "Connect", default: true) var connect: Bool

    init() {}
    init(serviceID: String, connect: Bool) {
        self.serviceID = serviceID
        self.connect = connect
    }

    func perform() async throws -> some IntentResult {
        RequestChannel.post(.vpn(id: serviceID, connect: connect))
        return .result()
    }
}
