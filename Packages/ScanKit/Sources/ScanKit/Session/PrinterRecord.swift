// A printer the user added.
import Foundation

/// One configured printer. `serviceName` is the Bonjour instance name (stable,
/// derived from the MAC address) and `uuid` the printer's announced UUID, both
/// nil for printers added by address; `host` is the last address that answered.
public struct PrinterRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var displayName: String
    public var serviceName: String?
    public var uuid: String?
    public var host: String
    public var port: Int

    public init(id: UUID = UUID(), displayName: String, serviceName: String? = nil, uuid: String? = nil,
                host: String, port: Int = 8080) {
        self.id = id
        self.displayName = displayName
        self.serviceName = serviceName
        self.uuid = uuid
        self.host = host
        self.port = port
    }

    public var address: String { "\(host):\(port)" }

    /// Found through Bonjour, so its presence on the current network can be
    /// checked by name instead of by address.
    public var isBonjour: Bool { serviceName != nil }

    /// True when both records describe the same physical printer: same UUID
    /// or Bonjour name when known, same address for printers added by hand.
    public func isSamePrinter(as other: PrinterRecord) -> Bool {
        if let a = uuid, let b = other.uuid { return a.caseInsensitiveCompare(b) == .orderedSame }
        if let a = serviceName, let b = other.serviceName { return a.caseInsensitiveCompare(b) == .orderedSame }
        if isBonjour != other.isBonjour { return false }
        return host.caseInsensitiveCompare(other.host) == .orderedSame && port == other.port
    }

    /// True when a discovered service is this printer.
    public func matches(_ scanner: DiscoveredScanner) -> Bool {
        if let uuid, let other = scanner.uuid { return uuid.caseInsensitiveCompare(other) == .orderedSame }
        guard let serviceName else { return false }
        return serviceName.caseInsensitiveCompare(scanner.serviceName) == .orderedSame
    }
}
