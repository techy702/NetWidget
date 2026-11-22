import Foundation

/// Fixed names shared by the app, the widget, the helper and the tests.
enum NW {
    static let appBundleID = "com.revtechdynamics.netwidget"
    static let helperBundleID = "com.revtechdynamics.netwidget.helper"
    static let helperMachService = "com.revtechdynamics.netwidget.helper"
    static let helperPlistName = "com.revtechdynamics.netwidget.helper.plist"

    /// The only exit node the widget can switch to (the M1 MacBook Air on the tailnet).
    static let exitNodeName = "v2"

    /// The Tailscale CLI inside the app bundle. /usr/local/bin/tailscale is a shell script that
    /// calls this same binary; calling it directly avoids running a shell.
    static let tailscaleBinary = "/Applications/Tailscale.app/Contents/MacOS/Tailscale"

    /// How many connections the widget shows. The full list stays in the app's memory.
    static let widgetConnectionLimit = 8

    /// Darwin notification the widget posts after queueing a toggle request.
    static let requestNotification = "com.revtechdynamics.netwidget.request"

    /// App Group shared by the app and the widget. Filled in at build time from Info.plist as
    /// "<TeamID>.com.revtechdynamics.netwidget"; the fallback only applies to unsigned test builds.
    static var appGroupID: String {
        (Bundle.main.object(forInfoDictionaryKey: "NWAppGroupID") as? String)
            .flatMap { $0.isEmpty ? nil : $0 } ?? "com.revtechdynamics.netwidget"
    }
}
