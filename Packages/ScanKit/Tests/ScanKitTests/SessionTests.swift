import Testing
import Foundation
@testable import ScanKit

struct PreferencesTests {
    @Test func formatForShortcut() {
        let p = ScanPreferences.defaults(deviceName: "x")
        #expect(p.format(forShortcut: "SavePDF") == .pdf)
        #expect(p.format(forShortcut: "SaveDocument1") == .pdf)
        #expect(p.format(forShortcut: "SavePhoto1") == .jpeg)
        #expect(p.format(forShortcut: "SaveJPEG") == .jpeg)
        #expect(p.format(forShortcut: "") == .pdf)
        var j = p
        j.format = .jpeg
        #expect(j.format(forShortcut: "") == .jpeg)
    }

    @Test func scanSettingsClamping() throws {
        var p = ScanPreferences.defaults(deviceName: "x")
        p.resolution = 600
        let caps = try ScanCaps.parse(Fixtures.scanCaps(adf: true))
        let platen = p.scanSettings(for: .platen, caps: caps)
        #expect(platen.width == ScanSettings.a4Width)
        #expect(platen.height == ScanSettings.a4Height)
        #expect(platen.resolution == 600)
        let adf = p.scanSettings(for: .adf, caps: caps)
        #expect(adf.resolution == 300) // clamped to the feeder's optical max
        #expect(adf.source == .adf)
        p.paper = .letter
        let letter = p.scanSettings(for: .platen, caps: caps)
        #expect(letter.width == ScanSettings.letterWidth)
        #expect(letter.height == ScanSettings.letterHeight)
    }

    @Test func validate() throws {
        var p = ScanPreferences.defaults(deviceName: "x")
        try p.validate()
        p.resolution = 50
        #expect(throws: (any Error).self) { try p.validate() }
        p.resolution = 300
        p.destinationName = " "
        #expect(throws: (any Error).self) { try p.validate() }
    }

    @Test func codableRoundTrip() throws {
        let p = ScanPreferences.defaults(deviceName: "Phone")
        let data = try JSONEncoder().encode(p)
        #expect(try JSONDecoder().decode(ScanPreferences.self, from: data) == p)
    }
}

struct EventTrackerTests {
    @Test func primeAndUnseen() throws {
        var t = EventTracker()
        let first = try EventTable.parse(Fixtures.eventTable(aging: 1), etag: "1")
        t.prime(with: first)
        #expect(t.unseen(in: first.events).isEmpty)
        let second = try EventTable.parse(Fixtures.eventTable(aging: 2), etag: "2")
        #expect(t.unseen(in: second.events).count == 1)
        #expect(t.unseen(in: second.events).isEmpty)
    }

    @Test func isForMe() {
        let mine = "/WalkupScanToComp/WalkupScanToCompDestinations/abc-123"
        let e = Event(category: "ScanEvent", agingStamp: "1", payloads: [
            Payload(resourceURI: "http://p:8080" + mine, resourceType: "wus:WalkupScanToCompDestination"),
        ])
        #expect(EventTracker.isForMe(e, destinationURI: mine))
        #expect(EventTracker.isForMe(Event(category: "ScanEvent", agingStamp: "1", payloads: [
            Payload(resourceURI: "/WalkupScanToCompDestinations/abc-123", resourceType: "Destination"),
        ]), destinationURI: mine))
        #expect(!(EventTracker.isForMe(Event(category: "ScanEvent", agingStamp: "1", payloads: [
            Payload(resourceURI: "/WalkupScanToComp/WalkupScanToCompDestinations/other", resourceType: "wus:WalkupScanToCompDestination"),
        ]), destinationURI: mine)))
        #expect(EventTracker.isForMe(Event(category: "ScanEvent", agingStamp: "1", payloads: [
            Payload(resourceURI: "/x", resourceType: "wus:WalkupScanToCompEvent"),
        ]), destinationURI: mine))
    }
}

struct DiscoveryFilterTests {
    @Test func scopeIsStripped() {
        #expect(EndpointResolver.stripScope("192.168.68.114%en0") == "192.168.68.114")
        #expect(EndpointResolver.stripScope("fe80::1%en0") == "fe80::1")
        #expect(EndpointResolver.stripScope("HP058DA0.local") == "HP058DA0.local")
        #expect(LEDMClient(host: "192.168.68.114%en0", port: 8080).baseURL.absoluteString == "http://192.168.68.114:8080")
    }

    @Test func isHP() {
        #expect(DiscoveredScanner.isHP(name: "Photosmart 6510 series [058DA0]", model: nil, mfg: "hp"))
        #expect(DiscoveredScanner.isHP(name: "HP OfficeJet Pro 9010", model: nil, mfg: nil))
        #expect(DiscoveredScanner.isHP(name: "Printer", model: "Photosmart 6510", mfg: nil))
        #expect(!(DiscoveredScanner.isHP(name: "Brother MFC", model: "MFC-L2710", mfg: "Brother")))
    }
}

struct PrinterSessionFlowTests {
    private func makeSession(_ printer: FakePrinter, sink: MemorySink, format: OutputFormat = .pdf) -> PrinterSession {
        var prefs = ScanPreferences.defaults(deviceName: "Test Phone")
        prefs.format = format
        let record = PrinterRecord(displayName: "Fake", host: "fake", port: 8080)
        return PrinterSession(printer: record, preferences: prefs, sink: sink, transport: printer)
    }

    private func waitReady(_ session: PrinterSession) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if await session.lastStatus.isReady { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private func waitStatus(_ session: PrinterSession, _ pred: @escaping (SessionStatus) -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if pred(await session.lastStatus) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    @Test func flatbedTwoPagePDF() async throws {
        let printer = FakePrinter()
        let sink = MemorySink()
        let session = makeSession(printer, sink: sink)
        let task = Task { await session.run() }
        #expect(await waitReady(session))
        await printer.fire("ScanRequested")
        #expect(await waitStatus(session) { if case .waitingForMorePages(1) = $0 { return true }; return false })
        await printer.fire("ScanNewPageRequested")
        #expect(await waitStatus(session) { if case .waitingForMorePages(2) = $0 { return true }; return false })
        await printer.fire("ScanPagesComplete")
        let files = await sink.waitForFiles(1)
        #expect(files.count == 1)
        #expect(files[0].name.hasSuffix(".pdf"))
        let s = String(decoding: files[0].data, as: UTF8.self)
        #expect(s.contains("/Count 2"))
        #expect(s.components(separatedBy: "/DCTDecode").count - 1 == 2)
        task.cancel()
        _ = await task.value
        let deletes = await printer.deletes
        #expect(deletes == 1)
        let scans = await printer.scans
        #expect(scans == 2)
    }

    @Test func feederRunIsOneDocument() async throws {
        let printer = FakePrinter()
        await printer.setAdfLoaded(true)
        let sink = MemorySink()
        let session = makeSession(printer, sink: sink)
        let task = Task { await session.run() }
        #expect(await waitReady(session))
        await printer.fire("ScanRequested")
        let files = await sink.waitForFiles(1)
        #expect(files.count == 1)
        #expect(String(decoding: files[0].data, as: UTF8.self).contains("/Count 2"))
        let scans = await printer.scans
        #expect(scans == 1)
        task.cancel()
        _ = await task.value
    }

    @Test func jPEGShortcutWritesPerPage() async throws {
        let printer = FakePrinter()
        await printer.setShortcut("SavePhoto1")
        let sink = MemorySink()
        let session = makeSession(printer, sink: sink)
        let task = Task { await session.run() }
        #expect(await waitReady(session))
        await printer.fire("ScanRequested")
        _ = await sink.waitForFiles(1)
        await printer.fire("ScanNewPageRequested")
        let files = await sink.waitForFiles(2)
        #expect(files.map(\.name).filter { $0.hasSuffix(".jpg") }.count == 2)
        #expect(files[0].data == Fixtures.jpeg(width: 30, height: 40, components: 3))
        task.cancel()
        _ = await task.value
    }

    @Test func vanishedDestinationReregisters() async throws {
        let printer = FakePrinter()
        let sink = MemorySink()
        let session = makeSession(printer, sink: sink)
        let task = Task { await session.run() }
        #expect(await waitReady(session))
        await printer.setDestinationMissing(true)
        await printer.fire("ScanRequested")
        let deadline = ContinuousClock.now + .seconds(5)
        while await printer.registrations < 2, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        let regs = await printer.registrations
        #expect(regs == 2)
        let scans = await printer.scans
        #expect(scans == 0)
        task.cancel()
        _ = await task.value
    }

    @Test func noETagPollingIsPaced() async throws {
        let printer = FakePrinter()
        await printer.setSendsETag(false)
        let session = makeSession(printer, sink: MemorySink())
        let task = Task { await session.run() }
        #expect(await waitReady(session))
        try await Task.sleep(for: .milliseconds(1500))
        let polls = await printer.requests.filter { $0 == "GET /EventMgmt/EventTable" }.count
        // About one per second; unpaced it would be hundreds.
        #expect(polls <= 4)
        task.cancel()
        _ = await task.value
    }

    @Test func idleSessionDoesNotScan() async throws {
        let printer = FakePrinter()
        let sink = MemorySink()
        let session = makeSession(printer, sink: sink)
        let task = Task { await session.run() }
        #expect(await waitReady(session))
        try await Task.sleep(for: .milliseconds(300))
        let scans = await printer.scans
        #expect(scans == 0)
        task.cancel()
        _ = await task.value
    }
}
