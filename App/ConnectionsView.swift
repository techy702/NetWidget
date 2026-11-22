import SwiftUI

/// Full connection list, like `sudo lsof -i -n -P`. Refreshes every 3 seconds while open.
struct ConnectionsView: View {
    @EnvironmentObject private var c: Controller
    @State private var filter = ""
    @State private var sortOrder = [KeyPathComparator(\Connection.command)]

    private var rows: [Connection] {
        let f = filter.trimmingCharacters(in: .whitespaces).lowercased()
        let list = f.isEmpty ? c.allConnections : c.allConnections.filter {
            "\($0.command) \($0.pid) \($0.proto) \($0.local) \($0.remote ?? "") \($0.state ?? "")"
                .lowercased().contains(f)
        }
        return list.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            if c.snapshot.helper != .ready {
                Text("Install and approve the helper from the menu bar to see connections for all processes.")
                    .padding()
            }
            Table(rows, sortOrder: $sortOrder) {
                TableColumn("Process", value: \.command)
                TableColumn("PID", value: \.pid) { Text(String($0.pid)) }.width(60)
                TableColumn("Proto", value: \.proto).width(50)
                TableColumn("Family", value: \.family).width(50)
                TableColumn("Local", value: \.local)
                TableColumn("Remote") { Text($0.remote ?? "") }
                TableColumn("State") { Text($0.state ?? "") }.width(100)
            }
            .font(.system(.body, design: .monospaced))
        }
        .searchable(text: $filter, prompt: "Filter")
        .navigationTitle("Connections (\(rows.count) of \(c.allConnections.count))")
        .onAppear { c.setLiveView(true) }
        .onDisappear { c.setLiveView(false) }
    }
}
