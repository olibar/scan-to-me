// Destination registration and walkup events, both LEDM flavours.
import Foundation

/// The two generations of HP scan-to-computer.
public enum WalkupFlavor: String, Sendable, Codable {
    /// 2009 REST flavour (/WalkupScan/...).
    case walkupScan = "WalkupScan"
    /// 2010 LEDM flavour (/WalkupScanToComp/...).
    case walkupScanToComp = "WalkupScanToComp"

    var destinationsPath: String {
        switch self {
        case .walkupScan: return "/WalkupScan/WalkupScanDestinations"
        case .walkupScanToComp: return "/WalkupScanToComp/WalkupScanToCompDestinations"
        }
    }
}

/// A registered "computer" as seen on the printer panel.
public struct Destination: Sendable, Equatable {
    public var uri: String
    public var name: String
    public var hostname: String
    /// e.g. SavePDF, SaveJPEG, SaveDocument1, SavePhoto1
    public var shortcut: String

    public init(uri: String = "", name: String = "", hostname: String = "", shortcut: String = "") {
        self.uri = uri
        self.name = name
        self.hostname = hostname
        self.shortcut = shortcut
    }

    /// Parses a destination document; `uri` is used when the body has no ResourceURI.
    public static func parse(_ data: Data, uri: String) throws -> Destination {
        let root = try XMLNode.parse(data)
        var d = Destination(uri: uri,
                            name: root.string("Name") ?? "",
                            hostname: root.string("Hostname") ?? "",
                            shortcut: root.string("WalkupScanToCompSettings/Shortcut") ?? "")
        if d.shortcut.isEmpty {
            d.shortcut = root.string("WalkupScanSettings/Shortcut") ?? ""
        }
        if d.uri.isEmpty {
            d.uri = root.string("ResourceURI") ?? ""
        }
        Log.ledm.debug("ledm: destination uri=\(d.uri) name=\(d.name) shortcut=\(d.shortcut)")
        return d
    }
}

/// Builds the registration body. The panel shows the Hostname field, so the
/// caller passes the display name for both.
func registrationXML(_ flavor: WalkupFlavor, name: String, hostname: String) -> String {
    let name = xmlEscape(name)
    let hostname = xmlEscape(hostname)
    switch flavor {
    case .walkupScanToComp:
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            + "<wus:WalkupScanToCompDestination xmlns:wus=\"http://www.hp.com/schemas/imaging/con/ledm/walkupscan/2010/09/28\""
            + " xmlns:dd=\"http://www.hp.com/schemas/imaging/con/dictionaries/1.0/\""
            + " xmlns:dd3=\"http://www.hp.com/schemas/imaging/con/dictionaries/2009/04/06\">"
            + "<dd3:Hostname>\(hostname)</dd3:Hostname>"
            + "<dd:Name>\(name)</dd:Name>"
            + "<wus:LinkType>Network</wus:LinkType>"
            + "</wus:WalkupScanToCompDestination>"
    case .walkupScan:
        return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            + "<wus:WalkupScanDestination xmlns:wus=\"http://www.hp.com/schemas/imaging/con/rest/walkupscan/2009/09/21\""
            + " xmlns:dd=\"http://www.hp.com/schemas/imaging/con/dictionaries/1.0/\">"
            + "<dd:Hostname>\(hostname)</dd:Hostname>"
            + "<dd:Name>\(name)</dd:Name>"
            + "<wus:LinkType>Network</wus:LinkType>"
            + "</wus:WalkupScanDestination>"
    }
}

/// Reduces an absolute Location URL to its path; some firmwares send one.
func locationPath(_ location: String) -> String {
    guard let schemeEnd = location.range(of: "://") else { return location }
    let rest = location[schemeEnd.upperBound...]
    guard let slash = rest.firstIndex(of: "/") else { return location }
    return String(rest[slash...])
}

/// Why a WalkupScanToComp ScanEvent fired.
public enum CompEventType: Sendable, Equatable {
    case hostSelected
    case scanRequested
    case scanNewPageRequested
    case scanPagesComplete
    case unknown(String)

    public static func parse(_ data: Data) throws -> CompEventType {
        let root = try XMLNode.parse(data)
        let raw = (root.string("WalkupScanToCompEventType") ?? root.text).trimmingCharacters(in: .whitespacesAndNewlines)
        let type = CompEventType(rawType: raw)
        Log.ledm.debug("ledm: walkup comp event \(raw)")
        return type
    }

    init(rawType: String) {
        switch rawType {
        case "HostSelected": self = .hostSelected
        case "ScanRequested": self = .scanRequested
        case "ScanNewPageRequested": self = .scanNewPageRequested
        case "ScanPagesComplete": self = .scanPagesComplete
        default: self = .unknown(rawType)
        }
    }

    public var rawType: String {
        switch self {
        case .hostSelected: return "HostSelected"
        case .scanRequested: return "ScanRequested"
        case .scanNewPageRequested: return "ScanNewPageRequested"
        case .scanPagesComplete: return "ScanPagesComplete"
        case let .unknown(s): return s
        }
    }
}
