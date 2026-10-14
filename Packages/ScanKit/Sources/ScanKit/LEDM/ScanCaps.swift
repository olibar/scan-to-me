// /Scan/ScanCaps and /Scan/Status.
import Foundation

/// Scan area (1/300 inch units) and resolution limits of one input source.
public struct SourceCaps: Sendable, Equatable {
    public var maxWidth = 0
    public var maxHeight = 0
    public var minResolution = 0
    public var maxResolution = 0
    public var maxOpticalX = 0

    public init(maxWidth: Int = 0, maxHeight: Int = 0, minResolution: Int = 0,
                maxResolution: Int = 0, maxOpticalX: Int = 0) {
        self.maxWidth = maxWidth
        self.maxHeight = maxHeight
        self.minResolution = minResolution
        self.maxResolution = maxResolution
        self.maxOpticalX = maxOpticalX
    }

    /// Highest usable resolution, 0 when the printer did not say.
    public var effectiveMaxResolution: Int {
        maxResolution > 0 ? maxResolution : maxOpticalX
    }

    static func parse(_ node: XMLNode) -> SourceCaps {
        SourceCaps(maxWidth: node.int("InputSourceCaps/MaxWidth") ?? 0,
                   maxHeight: node.int("InputSourceCaps/MaxHeight") ?? 0,
                   minResolution: node.int("InputSourceCaps/MinResolution") ?? 0,
                   maxResolution: node.int("InputSourceCaps/MaxResolution") ?? 0,
                   maxOpticalX: node.int("InputSourceCaps/MaxOpticalXResolution") ?? 0)
    }
}

/// Input sources the scanner offers.
public struct ScanCaps: Sendable, Equatable {
    public var platen = SourceCaps()
    public var adf: SourceCaps?

    public init(platen: SourceCaps = SourceCaps(), adf: SourceCaps? = nil) {
        self.platen = platen
        self.adf = adf
    }

    public var hasAdf: Bool { adf != nil }

    public static func parse(_ data: Data) throws -> ScanCaps {
        let root = try XMLNode.parse(data)
        var caps = ScanCaps()
        if let p = root.first("Platen") { caps.platen = SourceCaps.parse(p) }
        if let a = root.first("Adf") { caps.adf = SourceCaps.parse(a) }
        Log.ledm.debug("ledm: scan caps platen=\(caps.platen.maxWidth)x\(caps.platen.maxHeight) maxRes=\(caps.platen.effectiveMaxResolution) adf=\(caps.hasAdf)")
        return caps
    }
}

/// Idle/busy state of the scanner and the feeder.
public struct ScanStatus: Sendable, Equatable {
    public var scannerState = ""
    public var adfState = ""

    public init(scannerState: String = "", adfState: String = "") {
        self.scannerState = scannerState
        self.adfState = adfState
    }

    public var isIdle: Bool { scannerState.caseInsensitiveCompare("Idle") == .orderedSame }
    public var adfLoaded: Bool { adfState.caseInsensitiveCompare("Loaded") == .orderedSame }

    public static func parse(_ data: Data) throws -> ScanStatus {
        let root = try XMLNode.parse(data)
        let st = ScanStatus(scannerState: root.string("ScannerState") ?? "",
                            adfState: root.string("AdfState") ?? "")
        Log.ledm.debug("ledm: scan status scanner=\(st.scannerState) adf=\(st.adfState)")
        return st
    }
}
