import Foundation

/// The one file on disk: snapshot.json in the App Group container. Overwritten in place
/// (so it never grows) and deleted when the app quits.
enum SnapshotStore {
    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: NW.appGroupID)
    }

    static var fileURL: URL? { containerURL?.appendingPathComponent("snapshot.json") }

    static func read() -> Snapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return try? decoder.decode(Snapshot.self, from: data)
    }

    static func write(_ snapshot: Snapshot) throws {
        guard let dir = containerURL, let url = fileURL else { throw CocoaError(.fileNoSuchFile) }
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    static func delete() {
        guard let url = fileURL else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
