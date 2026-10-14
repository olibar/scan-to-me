import Testing
import Foundation
@testable import ScanKit

struct XMLNodeTests {
    @Test func localNamesAndPaths() throws {
        let root = try XMLNode.parse(Fixtures.scanCaps(adf: true))
        #expect(root.name == "ScanCaps")
        #expect(root.int("Platen/InputSourceCaps/MaxWidth") == 2550)
        #expect(root.all("Adf").count == 1)
        #expect(root.descendants("MaxWidth").count == 2)
        #expect(root.first("Nope/Deeper") == nil)
    }

    @Test func namespacedDocumentUsesLocalNames() throws {
        let root = try XMLNode.parse(Fixtures.eventTable(aging: 3))
        #expect(root.name == "EventTable")
        #expect(root.first("Event/UnqualifiedEventCategory")?.text == "ScanEvent")
    }

    @Test func malformedThrows() {
        #expect(throws: (any Error).self) { try XMLNode.parse(Data("<a><b></a>".utf8)) }
        #expect(throws: (any Error).self) { try XMLNode.parse(Data()) }
    }

    @Test func escape() {
        #expect(xmlEscape("A & B <c> \"q\"") == "A &amp; B &lt;c&gt; &quot;q&quot;")
    }
}

struct LEDMModelTests {
    @Test func discoveryTree() throws {
        let caps = try Capabilities.parse(Fixtures.discoveryTree)
        #expect(caps.walkupScanToComp)
        #expect(!(caps.walkupScan))
        #expect(caps.eventTable)
        #expect(caps.scan)
        #expect(caps.resources.count == 3)
        let legacy = try Capabilities.parse(Fixtures.discoveryTreeLegacy)
        #expect(legacy.walkupScan)
        #expect(!(legacy.walkupScanToComp))
        #expect(!(legacy.eventTable))
    }

    @Test func scanCaps() throws {
        let caps = try ScanCaps.parse(Fixtures.scanCaps(adf: true))
        #expect(caps.platen.maxWidth == 2550)
        #expect(caps.platen.maxHeight == 3508)
        #expect(caps.platen.effectiveMaxResolution == 1200)
        #expect(caps.adf?.effectiveMaxResolution == 300) // falls back to MaxOpticalXResolution
        #expect(try ScanCaps.parse(Fixtures.scanCaps(adf: false)).adf == nil)
    }

    @Test func scanStatus() throws {
        #expect(try ScanStatus.parse(Fixtures.status(adfLoaded: true)).adfLoaded)
        let idle = try ScanStatus.parse(Fixtures.status(adfLoaded: false))
        #expect(idle.isIdle)
        #expect(!(idle.adfLoaded))
    }

    @Test func registrationBody() {
        let comp = registrationXML(.walkupScanToComp, name: "A & B", hostname: "A & B")
        #expect(comp.contains("<dd3:Hostname>A &amp; B</dd3:Hostname>"))
        #expect(comp.contains("<dd:Name>A &amp; B</dd:Name>"))
        #expect(comp.contains("<wus:LinkType>Network</wus:LinkType>"))
        #expect(comp.contains("ledm/walkupscan/2010/09/28"))
        let old = registrationXML(.walkupScan, name: "N", hostname: "H")
        #expect(old.contains("<dd:Hostname>H</dd:Hostname>"))
        #expect(old.contains("rest/walkupscan/2009/09/21"))
    }

    @Test func destinationAndLocation() throws {
        let d = try Destination.parse(Fixtures.destination(shortcut: "SavePDF"), uri: "")
        #expect(d.shortcut == "SavePDF")
        #expect(d.name == "Test Mac")
        #expect(d.uri == "/WalkupScanToComp/WalkupScanToCompDestinations/abc-123")
        #expect(locationPath("http://192.168.1.2:8080/WalkupScanToComp/X/1") == "/WalkupScanToComp/X/1")
        #expect(locationPath("/WalkupScanToComp/X/1") == "/WalkupScanToComp/X/1")
    }

    @Test func compEvent() throws {
        #expect(try CompEventType.parse(Fixtures.compEvent("ScanRequested")) == .scanRequested)
        #expect(try CompEventType.parse(Fixtures.compEvent("ScanPagesComplete")) == .scanPagesComplete)
        #expect(try CompEventType.parse(Fixtures.compEvent("Weird")) == .unknown("Weird"))
    }

    @Test func eventTable() throws {
        let t = try EventTable.parse(Fixtures.eventTable(aging: 3), etag: "3")
        #expect(t.etag == "3")
        #expect(t.events.count == 1)
        #expect(t.events[0].category == "ScanEvent")
        #expect(t.events[0].agingStamp == "3-0")
        #expect(t.events[0].payloads.count == 2)
        #expect(t.events[0].payloads[0].resourceType == "wus:WalkupScanToCompDestination")
    }

    @Test func jobStatusAndFinished() throws {
        let processing = try JobStatus.parse(Fixtures.job(state: "Processing", pre: [(1, "ReadyToUpload", "/Scan/Pages/1")], post: []))
        #expect(processing.pre.first?.binaryURL == "/Scan/Pages/1")
        #expect(!(jobFinished(processing, source: .platen, pages: 0)))
        let uploaded = try JobStatus.parse(Fixtures.job(state: "Processing", pre: [], post: [(1, "UploadCompleted")]))
        #expect(jobFinished(uploaded, source: .platen, pages: 1))
        #expect(!(jobFinished(uploaded, source: .platen, pages: 0)))
        #expect(!(jobFinished(uploaded, source: .adf, pages: 1)))
        for state in ["Completed", "canceled", "Aborted"] {
            #expect(jobFinished(JobStatus(state: state, pre: [], post: []), source: .adf, pages: 0))
        }
    }

    @Test func scanSettingsXML() {
        let s = ScanSettings(resolution: 200, width: 100, height: 200, color: false, source: .adf)
        let xml = s.xml()
        #expect(xml.contains("<scan:XResolution>200</scan:XResolution>"))
        #expect(xml.contains("<scan:ColorSpace>Gray</scan:ColorSpace>"))
        #expect(xml.contains("<scan:InputSource>Adf</scan:InputSource>"))
        #expect(xml.contains("<scan:CompressionQFactor>15</scan:CompressionQFactor>"))
    }
}

struct ClientTests {
    @Test func pollEventsLongPollAnd304() async throws {
        let printer = FakePrinter()
        let client = LEDMClient(host: "fake", port: 8080, transport: printer)
        let (first, changed) = try await client.pollEvents(previous: EventTable(), waitSeconds: 0)
        #expect(changed)
        #expect(first.etag == "0")
        let (same, changed2) = try await client.pollEvents(previous: first, waitSeconds: 20)
        #expect(!(changed2))
        #expect(same == first)
        await printer.fire("ScanRequested")
        let (next, changed3) = try await client.pollEvents(previous: first, waitSeconds: 20)
        #expect(changed3)
        #expect(next.etag == "1")
    }

    @Test func registerReturnsLocation() async throws {
        let printer = FakePrinter()
        let client = LEDMClient(host: "fake", port: 8080, transport: printer)
        let uri = try await client.registerDestination(.walkupScanToComp, name: "Test Phone", hostname: "Test Phone")
        #expect(uri == "/WalkupScanToComp/WalkupScanToCompDestinations/abc-123")
        do {
            _ = try await client.registerDestination(.walkupScanToComp, name: "Wrong", hostname: "Wrong")
            Issue.record("expected 400")
        } catch let e as LEDMError {
            guard case .status(_, _, 400, _) = e else { Issue.record("\(e)"); return }
        }
    }

    @Test func notFoundDetection() async throws {
        let printer = FakePrinter()
        await printer.setDestinationMissing(true)
        let client = LEDMClient(host: "fake", port: 8080, transport: printer)
        do {
            _ = try await client.destination(at: printer.destURI)
            Issue.record("expected 404")
        } catch let e as LEDMError {
            #expect(e.isNotFound)
        }
    }
}
