import Foundation

// NetWidgetHelper: root launch daemon registered by the app through SMAppService.
// It does exactly one thing: list network connections across all processes (what
// `sudo lsof -i -n -P` shows). It accepts no input, writes no files and no logs, and only
// answers callers signed with this helper's own Team ID and the app's bundle identifier.
// launchd starts it on demand; it exits after a quiet minute.

final class HelperService: NSObject, NetWidgetHelperProtocol {
    func listConnections(reply: @escaping (Data?, String?) -> Void) {
        IdleTimer.shared.touch()
        do {
            let connections = try ConnectionLister.list()
            reply(try JSONEncoder().encode(connections), nil)
        } catch {
            reply(nil, "Could not list connections: \(error.localizedDescription)")
        }
    }
}

final class ListenerDelegate: NSObject, NSXPCListenerDelegate {
    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        // The code-signing requirement set on the listener has already been checked by the
        // system before this point; unsigned or foreign callers never get here.
        connection.exportedInterface = NSXPCInterface(with: NetWidgetHelperProtocol.self)
        connection.exportedObject = HelperService()
        connection.resume()
        IdleTimer.shared.touch()
        return true
    }
}

/// Exits the daemon after 60 seconds without a request, so it isn't resident when unused.
final class IdleTimer {
    static let shared = IdleTimer()
    private let queue = DispatchQueue(label: "idle")
    private var timer: DispatchSourceTimer?

    func touch() {
        queue.async {
            self.timer?.cancel()
            let t = DispatchSource.makeTimerSource(queue: self.queue)
            t.schedule(deadline: .now() + 60, leeway: .seconds(10))
            t.setEventHandler { exit(0) }
            t.resume()
            self.timer = t
        }
    }
}

// Refuse to run without a Developer ID signature: no Team ID means no way to check callers.
guard let teamID = CodeSigning.ownTeamID() else { exit(1) }

let listener = NSXPCListener(machServiceName: NW.helperMachService)
listener.setConnectionCodeSigningRequirement(
    CodeSigning.requirement(identifier: NW.appBundleID, teamID: teamID))
let delegate = ListenerDelegate()
listener.delegate = delegate
listener.resume()
IdleTimer.shared.touch()
dispatchMain()
