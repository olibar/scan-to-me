// /DevMgmt/DiscoveryTree.xml: which interfaces the printer offers.
import Foundation

/// Summary of the scan-to-computer flavours announced by a printer.
public struct Capabilities: Sendable, Equatable {
    public var walkupScanToComp = false
    public var walkupScan = false
    public var eventTable = false
    public var scan = false
    public var resources: [String] = []

    public static func parse(_ data: Data) throws -> Capabilities {
        let root = try XMLNode.parse(data)
        var caps = Capabilities()
        for ifc in root.descendants("SupportedIfc") {
            guard let uri = ifc.string("ManifestURI"), !uri.isEmpty else { continue }
            caps.resources.append(uri)
            if uri.hasPrefix("/WalkupScanToComp/") {
                caps.walkupScanToComp = true
            } else if uri.hasPrefix("/WalkupScan/") {
                caps.walkupScan = true
            } else if uri.hasPrefix("/EventMgmt/") {
                caps.eventTable = true
            } else if uri.hasPrefix("/Scan/") {
                caps.scan = true
            }
        }
        Log.ledm.debug("ledm: discovery walkupScanToComp=\(caps.walkupScanToComp) walkupScan=\(caps.walkupScan) eventTable=\(caps.eventTable) scan=\(caps.scan) resources=\(caps.resources.count)")
        return caps
    }
}
