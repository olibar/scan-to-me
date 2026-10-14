// A printer the user added.
import Foundation

/// One configured printer. `serviceName` is the Bonjour instance name (stable,
/// derived from the MAC address); `host` is the last address that answered.
public struct PrinterRecord: Codable, Identifiable, Hashable, Sendable {
    public var id: UUID
    public var displayName: String
    public var serviceName: String?
    public var host: String
    public var port: Int

    public init(id: UUID = UUID(), displayName: String, serviceName: String? = nil, host: String, port: Int = 8080) {
        self.id = id
        self.displayName = displayName
        self.serviceName = serviceName
        self.host = host
        self.port = port
    }

    public var address: String { "\(host):\(port)" }
}
