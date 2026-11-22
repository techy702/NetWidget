import SwiftUI

@main
struct NetWidgetApp: App {
    @StateObject private var controller = Controller()

    var body: some Scene {
        MenuBarExtra {
            MenuView().environmentObject(controller)
        } label: {
            Image(systemName: menuIcon)
        }
        .menuBarExtraStyle(.window)

        Window("Connections", id: "connections") {
            ConnectionsView().environmentObject(controller)
        }
        .defaultSize(width: 900, height: 520)
    }

    private var menuIcon: String {
        let s = controller.snapshot
        if s.tailscale.exitNode != nil || s.vpns.contains(where: \.isConnected) { return "lock.shield" }
        if s.wifi?.poweredOn == false && s.network.primaryInterface == nil { return "wifi.slash" }
        return "network"
    }
}
