// A _scanner._tcp service seen on the local network.
import Foundation
import Network

public struct DiscoveredScanner: Sendable, Identifiable, Hashable {
    /// Bonjour instance name, e.g. "Photosmart 6510 series [058DA0]".
    public let serviceName: String
    /// "ty" TXT record.
    public let model: String?
    /// "mfg" TXT record.
    public let mfg: String?
    public let endpoint: NWEndpoint

    public var id: String { serviceName }

    public init(serviceName: String, model: String?, mfg: String?, endpoint: NWEndpoint) {
        self.serviceName = serviceName
        self.model = model
        self.mfg = mfg
        self.endpoint = endpoint
    }

    public var isHP: Bool {
        DiscoveredScanner.isHP(name: serviceName, model: model, mfg: mfg)
    }

    static func isHP(name: String, model: String?, mfg: String?) -> Bool {
        if let mfg, mfg.caseInsensitiveCompare("HP") == .orderedSame { return true }
        if name.lowercased().contains("hp") { return true }
        if let model, model.lowercased().contains("photosmart") { return true }
        return false
    }

    public static func == (a: DiscoveredScanner, b: DiscoveredScanner) -> Bool { a.serviceName == b.serviceName }
    public func hash(into hasher: inout Hasher) { hasher.combine(serviceName) }
}
