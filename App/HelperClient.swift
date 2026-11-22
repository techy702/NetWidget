import Foundation
import ServiceManagement

/// Registers the root helper with SMAppService and calls it over XPC.
final class HelperClient {
    private let service = SMAppService.daemon(plistName: NW.helperPlistName)

    var state: HelperState {
        switch service.status {
        case .enabled: return .ready
        case .requiresApproval: return .needsApproval
        case .notRegistered, .notFound: return .notInstalled
        @unknown default: return .error
        }
    }

    /// Registers the daemon. macOS then asks you to approve it in System Settings > Login Items;
    /// this opens that pane when approval is pending.
    func install() throws {
        do {
            try service.register()
        } catch {
            if service.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
                return
            }
            throw error
        }
        if service.status == .requiresApproval { SMAppService.openSystemSettingsLoginItems() }
    }

    func uninstall() async throws {
        try await service.unregister()
    }

    /// Asks the helper for every connection on the Mac. Only talks to a helper signed with the
    /// same Team ID and the helper's bundle identifier.
    func listConnections() async throws -> [Connection] {
        guard let team = CodeSigning.ownTeamID() else {
            throw CommandError.failed("This build is not signed with a Developer ID, so the helper won't answer.")
        }
        let connection = NSXPCConnection(machServiceName: NW.helperMachService, options: .privileged)
        connection.remoteObjectInterface = NSXPCInterface(with: NetWidgetHelperProtocol.self)
        connection.setCodeSigningRequirement(CodeSigning.requirement(identifier: NW.helperBundleID, teamID: team))
        connection.resume()
        defer { connection.invalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            let once = ResumeOnce(continuation)
            let proxy = connection.remoteObjectProxyWithErrorHandler { error in
                once.resume(throwing: error)
            } as? NetWidgetHelperProtocol
            guard let proxy else {
                once.resume(throwing: CommandError.failed("Helper interface unavailable."))
                return
            }
            proxy.listConnections { data, message in
                if let data, let list = try? JSONDecoder().decode([Connection].self, from: data) {
                    once.resume(returning: list)
                } else {
                    once.resume(throwing: CommandError.failed(message ?? "Helper returned no data."))
                }
            }
        }
    }
}

/// XPC can call both the error handler and the reply; a continuation must resume exactly once.
private final class ResumeOnce<T> {
    private var continuation: CheckedContinuation<T, Error>?
    private let lock = NSLock()

    init(_ c: CheckedContinuation<T, Error>) { continuation = c }

    private func take() -> CheckedContinuation<T, Error>? {
        lock.lock(); defer { lock.unlock() }
        let c = continuation
        continuation = nil
        return c
    }

    func resume(returning value: T) { take()?.resume(returning: value) }
    func resume(throwing error: Error) { take()?.resume(throwing: error) }
}
