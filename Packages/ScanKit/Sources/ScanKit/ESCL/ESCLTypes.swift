// eSCL documents: scanner capabilities and status, walkup events and the
// scan job request. Element names are matched by local name like the LEDM
// documents; request bodies reproduce what the printer is known to accept.
import Foundation

/// The subset of /eSCL/ScannerCapabilities the session needs.
public struct ESCLCaps: Sendable, Equatable {
    public var makeAndModel = ""
    /// Platen and feeder limits in the shape the LEDM path already uses, so
    /// paper size and resolution clamping is shared.
    public var scanCaps = ScanCaps()
    public var hasAdfDuplex = false
    /// The scanner reports honestly whether the feeder holds paper. Without
    /// it, AdfState cannot be trusted to choose between feeder and flatbed.
    public var detectsPaperLoaded = false

    public init() {}

    static func parse(_ data: Data) throws -> ESCLCaps {
        let root = try XMLNode.parse(data)
        var caps = ESCLCaps()
        caps.makeAndModel = root.string("MakeAndModel") ?? ""
        if let platen = root.first("Platen/PlatenInputCaps") {
            caps.scanCaps.platen = sourceCaps(platen)
        }
        if let adf = root.first("Adf/AdfSimplexInputCaps") {
            caps.scanCaps.adf = sourceCaps(adf)
        }
        caps.hasAdfDuplex = root.first("Adf/AdfDuplexInputCaps") != nil
        let options = root.first("Adf/AdfOptions")?.all("AdfOption").map(\.text) ?? []
        caps.detectsPaperLoaded = options.contains { $0.caseInsensitiveCompare("DetectPaperLoaded") == .orderedSame }
        Log.escl.debug("escl: caps model=\(caps.makeAndModel) platen=\(caps.scanCaps.platen.maxWidth)x\(caps.scanCaps.platen.maxHeight) maxRes=\(caps.scanCaps.platen.maxResolution) adf=\(caps.scanCaps.hasAdf) duplex=\(caps.hasAdfDuplex) detectPaper=\(caps.detectsPaperLoaded)")
        return caps
    }

    private static func sourceCaps(_ node: XMLNode) -> SourceCaps {
        let resolutions = node.descendants("DiscreteResolution").compactMap { $0.int("XResolution") }
        return SourceCaps(maxWidth: node.int("MaxWidth") ?? 0,
                          maxHeight: node.int("MaxHeight") ?? 0,
                          minResolution: resolutions.min() ?? 0,
                          maxResolution: resolutions.max() ?? 0)
    }
}

/// /eSCL/ScannerStatus.
public struct ESCLStatus: Sendable, Equatable {
    public var state: String
    public var adfState: String

    public var isIdle: Bool { state.caseInsensitiveCompare("Idle") == .orderedSame }
    /// Only meaningful when ESCLCaps.detectsPaperLoaded is true.
    public var paperLoaded: Bool { adfState.caseInsensitiveCompare("ScannerAdfLoaded") == .orderedSame }

    static func parse(_ data: Data) throws -> ESCLStatus {
        let root = try XMLNode.parse(data)
        let st = ESCLStatus(state: root.string("State") ?? "", adfState: root.string("AdfState") ?? "")
        Log.escl.debug("escl: status state=\(st.state) adf=\(st.adfState)")
        return st
    }
}

/// One instruction from the printer's panel. The event types are the same
/// four the LEDM WalkupScanToComp flavour uses.
public struct WalkupEvent: Sendable, Equatable {
    public var type: CompEventType
    /// Name of the shortcut the user picked; the only hint for the format.
    public var shortcut: String
    /// Resolution chosen on the panel, 0 when not sent.
    public var resolution: Int
    public var duplex: Bool

    public init(type: CompEventType, shortcut: String = "", resolution: Int = 0, duplex: Bool = false) {
        self.type = type
        self.shortcut = shortcut
        self.resolution = resolution
        self.duplex = duplex
    }

    static func parse(_ data: Data) throws -> WalkupEvent {
        let root = try XMLNode.parse(data)
        let ev = WalkupEvent(type: CompEventType(rawType: (root.string("Event") ?? "").trimmingCharacters(in: .whitespacesAndNewlines)),
                             shortcut: root.string("Shortcut") ?? "",
                             resolution: root.int("ScanSettings/XResolution") ?? 0,
                             duplex: (root.string("ScanSettings/Duplex") ?? "").lowercased() == "true")
        Log.escl.debug("escl: walkup event type=\(ev.type.rawType) shortcut=\(ev.shortcut) resolution=\(ev.resolution) duplex=\(ev.duplex)")
        return ev
    }
}

/// Shortcut names offered on the panel. The format is read back from the one
/// the user picks, so the names must contain "PDF" and "JPEG".
let esclShortcuts = ["Save as PDF", "Save as JPEG"]

/// Longest destination and shortcut name the panel accepts (UTF-8 bytes);
/// longer names are truncated silently by the printer.
let esclMaxNameBytes = 32

/// Cuts a name to what the panel accepts without splitting a character.
func esclTruncatedName(_ name: String) -> String {
    var out = ""
    for ch in name {
        if out.utf8.count + String(ch).utf8.count > esclMaxNameBytes { break }
        out.append(ch)
    }
    return out
}

/// One eSCL scan job. Built from the LEDM-shaped settings so clamping is
/// shared, plus the fields that tie the job to the panel session.
struct ESCLScanSettings: Sendable, Equatable {
    var base: ScanSettings
    var duplex = false
    /// The subscription id. Without it the printer treats the job as an
    /// unrelated pull scan and never offers "another page or done?".
    var contextID = ""
    /// Shown as the requesting machine; the scanner asks for JobSourceInfo.
    var machineName = ""

    var isFeeder: Bool { base.source == .adf }

    /// Request body. Measured against HP firmware, not the spec: ScanRegions
    /// and ScanRegion are in the scan: namespace (a pwg: one is rejected with
    /// a bare 409), the format goes in scan:DocumentFormatExt, and Duplex is
    /// sent for feeder jobs only - even "false" on a flatbed job makes the
    /// printer close the job after one page.
    func xml() -> String {
        let pwg = "http://www.pwg.org/schemas/2010/12/sm"
        let scan = "http://schemas.hp.com/imaging/escl/2011/05/03"
        var s = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>"
            + "<scan:ScanSettings xmlns:pwg=\"\(pwg)\" xmlns:scan=\"\(scan)\" xmlns:escl=\"\(scan)\">"
            + "<pwg:Version>2.9</pwg:Version>"
        if !contextID.isEmpty { s += "<scan:ContextID>\(xmlEscape(contextID))</scan:ContextID>" }
        s += "<scan:Intent>Document</scan:Intent>"
        if base.width > 0, base.height > 0 {
            s += "<scan:ScanRegions><scan:ScanRegion>"
                + "<pwg:Height>\(base.height)</pwg:Height>"
                + "<pwg:ContentRegionUnits>escl:ThreeHundredthsOfInch</pwg:ContentRegionUnits>"
                + "<pwg:Width>\(base.width)</pwg:Width>"
                + "<pwg:XOffset>0</pwg:XOffset><pwg:YOffset>0</pwg:YOffset>"
                + "</scan:ScanRegion></scan:ScanRegions>"
        }
        s += "<scan:DocumentFormatExt>image/jpeg</scan:DocumentFormatExt>"
            + "<pwg:InputSource>\(isFeeder ? "Feeder" : "Platen")</pwg:InputSource>"
            + "<scan:XResolution>\(base.resolution)</scan:XResolution>"
            + "<scan:YResolution>\(base.resolution)</scan:YResolution>"
            + "<scan:ColorMode>\(base.color ? "RGB24" : "Grayscale8")</scan:ColorMode>"
        if isFeeder { s += "<scan:Duplex>\(duplex)</scan:Duplex>" }
        if !machineName.isEmpty {
            // The printer's own client sends these children without a prefix.
            s += "<scan:JobSourceInfo><UserName></UserName><UserDomain></UserDomain>"
                + "<MachineName>\(xmlEscape(machineName))</MachineName>"
                + "<AppFileName>ScanToMe</AppFileName><Application>Scan to Me</Application></scan:JobSourceInfo>"
        }
        return s + "</scan:ScanSettings>"
    }
}
