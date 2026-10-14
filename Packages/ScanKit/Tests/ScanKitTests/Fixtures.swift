// XML documents as produced by a WalkupScanToComp printer, plus a synthetic
// JPEG header builder.
import Foundation

enum Fixtures {
    static let discoveryTree = Data("""
    <ledm:DiscoveryTree xmlns:ledm="x" xmlns:dd="y">
    <ledm:SupportedIfc><dd:ResourceType>ledm:hpLedmWalkupScanToCompManifest</dd:ResourceType><ledm:ManifestURI>/WalkupScanToComp/WalkupScanToCompManifest.xml</ledm:ManifestURI></ledm:SupportedIfc>
    <ledm:SupportedIfc><ledm:ManifestURI>/EventMgmt/EventMgmtManifest.xml</ledm:ManifestURI></ledm:SupportedIfc>
    <ledm:SupportedIfc><ledm:ManifestURI>/Scan/ScanManifest.xml</ledm:ManifestURI></ledm:SupportedIfc>
    </ledm:DiscoveryTree>
    """.utf8)

    static let discoveryTreeLegacy = Data("""
    <ledm:DiscoveryTree xmlns:ledm="x" xmlns:dd="y">
    <ledm:SupportedIfc><ledm:ManifestURI>/WalkupScan/WalkupScanManifest.xml</ledm:ManifestURI></ledm:SupportedIfc>
    <ledm:SupportedIfc><ledm:ManifestURI>/Scan/ScanManifest.xml</ledm:ManifestURI></ledm:SupportedIfc>
    </ledm:DiscoveryTree>
    """.utf8)

    static func scanCaps(adf: Bool) -> Data {
        let a = adf ? "<Adf><InputSourceCaps><MaxWidth>2550</MaxWidth><MaxHeight>4200</MaxHeight><MaxOpticalXResolution>300</MaxOpticalXResolution></InputSourceCaps></Adf>" : ""
        return Data(("<ScanCaps><Platen><InputSourceCaps><MaxWidth>2550</MaxWidth><MaxHeight>3508</MaxHeight><MaxResolution>1200</MaxResolution></InputSourceCaps></Platen>" + a + "</ScanCaps>").utf8)
    }

    static func status(adfLoaded: Bool) -> Data {
        Data("<ScanStatus><ScannerState>Idle</ScannerState><AdfState>\(adfLoaded ? "Loaded" : "Empty")</AdfState></ScanStatus>".utf8)
    }

    static func destination(shortcut: String) -> Data {
        Data("<wus:WalkupScanToCompDestination xmlns:wus=\"x\" xmlns:dd=\"y\"><dd:Name>Test Mac</dd:Name><dd:ResourceURI>/WalkupScanToComp/WalkupScanToCompDestinations/abc-123</dd:ResourceURI><wus:WalkupScanToCompSettings><wus:Shortcut>\(shortcut)</wus:Shortcut></wus:WalkupScanToCompSettings></wus:WalkupScanToCompDestination>".utf8)
    }

    static func compEvent(_ type: String) -> Data {
        Data("<wus:WalkupScanToCompEvent xmlns:wus=\"x\"><wus:WalkupScanToCompEventType>\(type)</wus:WalkupScanToCompEventType></wus:WalkupScanToCompEvent>".utf8)
    }

    static func eventTable(aging: Int, destination: String = "/WalkupScanToComp/WalkupScanToCompDestinations/abc-123") -> Data {
        Data("<ev:EventTable xmlns:ev=\"x\" xmlns:dd=\"y\"><ev:Event><dd:UnqualifiedEventCategory>ScanEvent</dd:UnqualifiedEventCategory><dd:AgingStamp>\(aging)-0</dd:AgingStamp><ev:Payload><dd:ResourceURI>\(destination)</dd:ResourceURI><dd:ResourceType>wus:WalkupScanToCompDestination</dd:ResourceType></ev:Payload><ev:Payload><dd:ResourceURI>/WalkupScanToComp/WalkupScanToCompEvent</dd:ResourceURI><dd:ResourceType>wus:WalkupScanToCompEvent</dd:ResourceType></ev:Payload></ev:Event></ev:EventTable>".utf8)
    }

    static func job(state: String, pre: [(Int, String, String?)], post: [(Int, String)]) -> Data {
        var s = "<j:Job xmlns:j=\"x\"><j:JobState>\(state)</j:JobState><j:ScanJob>"
        for (n, st, url) in pre {
            s += "<j:PreScanPage><j:PageNumber>\(n)</j:PageNumber><j:PageState>\(st)</j:PageState>"
            if let url { s += "<j:BinaryURL>\(url)</j:BinaryURL>" }
            s += "</j:PreScanPage>"
        }
        for (n, st) in post {
            s += "<j:PostScanPage><j:PageNumber>\(n)</j:PageNumber><j:PageState>\(st)</j:PageState></j:PostScanPage>"
        }
        s += "</j:ScanJob></j:Job>"
        return Data(s.utf8)
    }

    /// A syntactically valid JPEG skeleton: SOI, SOF0 with the given geometry, EOI.
    static func jpeg(width: Int, height: Int, components: Int, progressive: Bool = false) -> Data {
        var b: [UInt8] = [0xFF, 0xD8]
        // APP0 segment to make sure the parser skips non-SOF segments.
        b += [0xFF, 0xE0, 0x00, 0x04, 0x4A, 0x46]
        let sofLen = 8 + components * 3
        b += [0xFF, progressive ? 0xC2 : 0xC0, UInt8(sofLen >> 8), UInt8(sofLen & 0xFF), 8,
              UInt8(height >> 8), UInt8(height & 0xFF), UInt8(width >> 8), UInt8(width & 0xFF), UInt8(components)]
        for c in 0..<components { b += [UInt8(c + 1), 0x11, 0x00] }
        b += [0xFF, 0xD9]
        return Data(b)
    }
}
