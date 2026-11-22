import Foundation

/// The complete list of commands the app may run. Each case maps to one absolute program path
/// and a fixed argument list. The only variable parts are a Wi-Fi interface name and a VPN
/// service ID, and both must match values read from the system at the moment of the call.
/// There is no way to run anything else.
enum AllowedCommand: Equatable {
    case wifiPower(interface: String, on: Bool)
    case tailscaleStatus
    case tailscaleUp
    case tailscaleDown
    case exitNodeOn
    case exitNodeOff
    case vpnList
    case vpnStart(id: String)
    case vpnStop(id: String)
}

/// Values read from the system just before running a command, used to validate it.
struct CommandContext {
    /// Wi-Fi interface names reported by CoreWLAN.
    var wifiInterfaces: Set<String> = []
    /// VPN service IDs from `scutil --nc list`, with Tailscale's entry already removed.
    var vpnIDs: Set<String> = []
}

enum CommandError: Error, Equatable, LocalizedError {
    case unknownWiFiInterface(String)
    case unknownVPN(String)
    case tailscaleNotInstalled
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .unknownWiFiInterface(let i): return "Refused: \(i) is not a Wi-Fi interface on this Mac."
        case .unknownVPN(let id): return "Refused: \(id) is not a configured VPN."
        case .tailscaleNotInstalled: return "Tailscale is not installed in /Applications."
        case .failed(let m): return m
        }
    }
}

extension AllowedCommand {
    static let networksetup = "/usr/sbin/networksetup"
    static let scutil = "/usr/sbin/scutil"

    /// The exact program and arguments for this command, after validation.
    func invocation(in context: CommandContext) throws -> (path: String, arguments: [String]) {
        switch self {
        case let .wifiPower(interface, on):
            guard context.wifiInterfaces.contains(interface) else {
                throw CommandError.unknownWiFiInterface(interface)
            }
            return (Self.networksetup, ["-setairportpower", interface, on ? "on" : "off"])
        case .tailscaleStatus:
            return (NW.tailscaleBinary, ["status", "--json"])
        case .tailscaleUp:
            return (NW.tailscaleBinary, ["up"])
        case .tailscaleDown:
            return (NW.tailscaleBinary, ["down"])
        case .exitNodeOn:
            return (NW.tailscaleBinary, ["set", "--exit-node=\(NW.exitNodeName)"])
        case .exitNodeOff:
            return (NW.tailscaleBinary, ["set", "--exit-node="])
        case .vpnList:
            return (Self.scutil, ["--nc", "list"])
        case let .vpnStart(id):
            guard context.vpnIDs.contains(id) else { throw CommandError.unknownVPN(id) }
            return (Self.scutil, ["--nc", "start", id])
        case let .vpnStop(id):
            guard context.vpnIDs.contains(id) else { throw CommandError.unknownVPN(id) }
            return (Self.scutil, ["--nc", "stop", id])
        }
    }

    var usesTailscale: Bool {
        switch self {
        case .tailscaleStatus, .tailscaleUp, .tailscaleDown, .exitNodeOn, .exitNodeOff: return true
        default: return false
        }
    }

    /// Validates and runs the command. Must be called off the main thread.
    func run(in context: CommandContext = CommandContext(), timeout: TimeInterval = 10) throws -> ProcessResult {
        let (path, arguments) = try invocation(in: context)
        if usesTailscale && !FileManager.default.isExecutableFile(atPath: path) {
            throw CommandError.tailscaleNotInstalled
        }
        return try ProcessRunner.run(path, arguments, timeout: timeout)
    }
}
