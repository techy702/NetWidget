import Foundation

/// A toggle the widget asks for. It carries the desired end state, not "flip", so a repeated
/// or late request can't undo itself.
enum ToggleRequest: Codable, Equatable {
    case wifi(on: Bool)
    case tailscale(up: Bool)
    case exitNode(on: Bool)
    case vpn(id: String, connect: Bool)
}

/// Widget-to-app channel: the widget appends a request to requests.json in the App Group and
/// posts a Darwin notification (a payload-free, system-wide ping). The app reads the file,
/// deletes it, and runs each request through its fixed command list.
enum RequestChannel {
    private static var fileURL: URL? { SnapshotStore.containerURL?.appendingPathComponent("requests.json") }
    /// Caps the queue so a stuck app can't let the file grow.
    private static let maxQueued = 8

    static func post(_ request: ToggleRequest) {
        guard let dir = SnapshotStore.containerURL, let url = fileURL else { return }
        var queue = load()
        queue.append(request)
        queue = Array(queue.suffix(maxQueued))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(queue).write(to: url, options: .atomic)
        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(NW.requestNotification as CFString), nil, nil, true)
    }

    /// Returns the queued requests and deletes the file.
    static func consume() -> [ToggleRequest] {
        let queue = load()
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        return queue
    }

    private static func load() -> [ToggleRequest] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([ToggleRequest].self, from: data)) ?? []
    }
}
