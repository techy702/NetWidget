import Foundation

/// The helper's single command, fixed: `/usr/sbin/lsof -i -n -P -F pcPtnT`.
/// -i internet sockets only, -n no DNS lookups, -P no port-name lookups (so lsof itself makes
/// no network calls), -F machine-readable fields.
enum ConnectionLister {
    static let path = "/usr/sbin/lsof"
    static let arguments = ["-i", "-n", "-P", "-F", "pcPtnT"]

    static func list() throws -> [Connection] {
        let result = try ProcessRunner.run(path, arguments, timeout: 10)
        // lsof exits 1 when some descriptors vanish mid-scan but still prints the rest,
        // so the output is used whatever the status, unless it timed out.
        if result.timedOut { throw CocoaError(.executableLoad) }
        return LsofParser.parse(result.stdout)
    }
}
