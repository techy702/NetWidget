import Foundation

/// The root helper's whole interface: one call, no arguments. Replies with JSON-encoded
/// [Connection] or an error string.
@objc protocol NetWidgetHelperProtocol {
    func listConnections(reply: @escaping (Data?, String?) -> Void)
}
