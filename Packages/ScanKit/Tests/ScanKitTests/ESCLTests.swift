// eSCL: document parsing, request bodies, and the session against a fake
// eSCL-only printer (no LEDM DiscoveryTree).
import Foundation
import Testing
@testable import ScanKit

enum ESCLFixtures {
    static func caps(adf: Bool) -> Data {
        let feeder = adf ? """
        <scan:Adf><scan:AdfSimplexInputCaps><scan:MaxWidth>2550</scan:MaxWidth><scan:MaxHeight>4200</scan:MaxHeight>
        <scan:SettingProfiles><scan:SettingProfile><scan:SupportedResolutions><scan:DiscreteResolutions>
        <scan:DiscreteResolution><scan:XResolution>300</scan:XResolution><scan:YResolution>300</scan:YResolution></scan:DiscreteResolution>
        </scan:DiscreteResolutions></scan:SupportedResolutions></scan:SettingProfile></scan:SettingProfiles></scan:AdfSimplexInputCaps>
        <scan:AdfDuplexInputCaps><scan:MaxWidth>2550</scan:MaxWidth></scan:AdfDuplexInputCaps>
        <scan:AdfOptions><scan:AdfOption>DetectPaperLoaded</scan:AdfOption><scan:AdfOption>Duplex</scan:AdfOption></scan:AdfOptions></scan:Adf>
        """ : ""
        return Data("""
        <scan:ScannerCapabilities xmlns:scan="http://schemas.hp.com/imaging/escl/2011/05/03" xmlns:pwg="http://www.pwg.org/schemas/2010/12/sm">
        <pwg:Version>2.9</pwg:Version><pwg:MakeAndModel>Fake Printer 9100</pwg:MakeAndModel>
        <scan:Platen><scan:PlatenInputCaps><scan:MaxWidth>2550</scan:MaxWidth><scan:MaxHeight>3508</scan:MaxHeight>
        <scan:SettingProfiles><scan:SettingProfile><scan:SupportedResolutions><scan:DiscreteResolutions>
        <scan:DiscreteResolution><scan:XResolution>75</scan:XResolution><scan:YResolution>75</scan:YResolution></scan:DiscreteResolution>
        <scan:DiscreteResolution><scan:XResolution>1200</scan:XResolution><scan:YResolution>1200</scan:YResolution></scan:DiscreteResolution>
        <scan:DiscreteResolution><scan:XResolution>300</scan:XResolution><scan:YResolution>300</scan:YResolution></scan:DiscreteResolution>
        </scan:DiscreteResolutions></scan:SupportedResolutions></scan:SettingProfile></scan:SettingProfiles></scan:PlatenInputCaps></scan:Platen>
        \(feeder)
        </scan:ScannerCapabilities>
        """.utf8)
    }

    static func status(adfLoaded: Bool) -> Data {
        Data("<scan:ScannerStatus xmlns:scan=\"s\" xmlns:pwg=\"p\"><pwg:Version>2.9</pwg:Version><pwg:State>Idle</pwg:State><scan:AdfState>\(adfLoaded ? "ScannerAdfLoaded" : "ScannerAdfEmpty")</scan:AdfState></scan:ScannerStatus>".utf8)
    }

    static func event(_ type: String, shortcut: String = "Save as PDF", resolution: Int = 0) -> Data {
        let settings = resolution > 0 ? "<scan:ScanSettings><scan:XResolution>\(resolution)</scan:XResolution><scan:Duplex>false</scan:Duplex></scan:ScanSettings>" : ""
        return Data("<scan:WalkupScanEvent xmlns:scan=\"s\"><scan:ResourceURI>/eSCL/WalkupSubscriptions/sub-1</scan:ResourceURI><scan:HostIdentifier>Test Phone</scan:HostIdentifier><scan:Event>\(type)</scan:Event><scan:Shortcut>\(shortcut)</scan:Shortcut>\(settings)</scan:WalkupScanEvent>".utf8)
    }
}

/// An eSCL-only printer: LEDM is absent, walkup goes through subscriptions.
actor FakeESCLPrinter: HTTPTransport {
    var subscriptions = 0
    var unsubscribes = 0
    var subscriptionMissing = false
    var adfLoaded = false
    var busyOnce = false
    var pending: [Data] = []
    var jobBodies: [String] = []
    var pagesLeft: [Int: Int] = [:]
    var jobDeletes = 0
    var requests: [String] = []
    let jpeg = Fixtures.jpeg(width: 30, height: 40, components: 3)

    func push(_ event: Data) { pending.append(event) }
    func setAdfLoaded(_ v: Bool) { adfLoaded = v }
    func setBusyOnce(_ v: Bool) { busyOnce = v }
    func setSubscriptionMissing(_ v: Bool) { subscriptionMissing = v }

    var subURI: String { "/eSCL/WalkupSubscriptions/sub-\(subscriptions)" }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let path = url.path
        let method = request.httpMethod ?? "GET"
        requests.append("\(method) \(path)")
        func reply(_ status: Int, _ body: Data = Data(), headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
            (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
        }
        switch (method, path) {
        case ("GET", "/eSCL/ScannerStatus"):
            return reply(200, ESCLFixtures.status(adfLoaded: adfLoaded))
        case ("GET", "/eSCL/ScannerCapabilities"):
            return reply(200, ESCLFixtures.caps(adf: true))
        case ("POST", "/eSCL/WalkupSubscriptions"):
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            guard body.contains("<scan:HostIdentifier>Test Phone</scan:HostIdentifier>"),
                  body.contains("<scan:Shortcut>Save as PDF</scan:Shortcut>") else { return reply(400) }
            subscriptions += 1
            subscriptionMissing = false
            return reply(201, headers: ["Location": subURI])
        case ("GET", subURI + "/Event"):
            if subscriptionMissing { return reply(404) }
            if pending.isEmpty { return reply(204) }
            return reply(200, pending.removeFirst())
        case ("DELETE", subURI):
            unsubscribes += 1
            return reply(200)
        case ("POST", "/eSCL/ScanJobs"):
            if busyOnce {
                busyOnce = false
                return reply(503)
            }
            jobBodies.append(String(decoding: request.httpBody ?? Data(), as: UTF8.self))
            let n = jobBodies.count
            pagesLeft[n] = adfLoaded ? 2 : 1
            // A server-absolute path: the form that must not become /eSCL/eSCL/...
            return reply(201, headers: ["Location": "/eSCL/ScanJobs/\(n)"])
        case ("GET", _) where path.hasPrefix("/eSCL/ScanJobs/") && path.hasSuffix("/NextDocument"):
            let n = Int(path.split(separator: "/")[2]) ?? 0
            guard let left = pagesLeft[n], left > 0 else { return reply(404) }
            pagesLeft[n] = left - 1
            return reply(200, jpeg, headers: ["Content-Type": "image/jpeg"])
        case ("DELETE", _) where path.hasPrefix("/eSCL/ScanJobs/"):
            jobDeletes += 1
            return reply(200)
        default:
            return reply(404, Data("no route \(method) \(path)".utf8))
        }
    }
}

extension PrinterSession {
    func setESCLPollInterval(_ d: Duration) { esclPollInterval = d }
}

struct ESCLParsingTests {
    @Test func capabilitiesMapToScanCaps() throws {
        let caps = try ESCLCaps.parse(ESCLFixtures.caps(adf: true))
        #expect(caps.makeAndModel == "Fake Printer 9100")
        #expect(caps.scanCaps.platen.maxWidth == 2550)
        #expect(caps.scanCaps.platen.maxHeight == 3508)
        #expect(caps.scanCaps.platen.maxResolution == 1200)
        #expect(caps.scanCaps.platen.minResolution == 75)
        #expect(caps.scanCaps.adf?.maxResolution == 300)
        #expect(caps.hasAdfDuplex)
        #expect(caps.detectsPaperLoaded)
        let flatOnly = try ESCLCaps.parse(ESCLFixtures.caps(adf: false))
        #expect(flatOnly.scanCaps.adf == nil)
        #expect(!flatOnly.detectsPaperLoaded)
    }

    @Test func statusAndEvent() throws {
        let st = try ESCLStatus.parse(ESCLFixtures.status(adfLoaded: true))
        #expect(st.isIdle && st.paperLoaded)
        let ev = try WalkupEvent.parse(ESCLFixtures.event("ScanRequested", shortcut: "Save as JPEG", resolution: 600))
        #expect(ev == WalkupEvent(type: .scanRequested, shortcut: "Save as JPEG", resolution: 600, duplex: false))
    }

    @Test func scanSettingsBody() {
        let base = ScanSettings(resolution: 300, width: 2481, height: 3507, color: true)
        var s = ESCLScanSettings(base: base, contextID: "sub-1", machineName: "Phone & Co")
        let flat = s.xml()
        #expect(flat.contains("<scan:ScanRegions><scan:ScanRegion><pwg:Height>3507</pwg:Height>"))
        #expect(flat.contains("<pwg:InputSource>Platen</pwg:InputSource>"))
        #expect(!flat.contains("Duplex"))
        #expect(flat.contains("<scan:ColorMode>RGB24</scan:ColorMode>"))
        #expect(flat.contains("<MachineName>Phone &amp; Co</MachineName>"))
        let context = flat.range(of: "<scan:ContextID>sub-1</scan:ContextID>")
        let intent = flat.range(of: "<scan:Intent>Document</scan:Intent>")
        #expect(context != nil && intent != nil && context!.lowerBound < intent!.lowerBound)
        s.base.source = .adf
        s.base.color = false
        let feeder = s.xml()
        #expect(feeder.contains("<pwg:InputSource>Feeder</pwg:InputSource>"))
        #expect(feeder.contains("<scan:Duplex>false</scan:Duplex>"))
        #expect(feeder.contains("<scan:ColorMode>Grayscale8</scan:ColorMode>"))
    }

    @Test func subscriptionBodyAndNames() {
        let body = registrationXML(.escl, name: "A<B", hostname: "A<B")
        #expect(body.contains("<scan:HostIdentifier>A&lt;B</scan:HostIdentifier>"))
        #expect(body.contains("<scan:Shortcut>Save as PDF</scan:Shortcut><scan:Shortcut>Save as JPEG</scan:Shortcut>"))
        #expect(esclTruncatedName(String(repeating: "x", count: 40)).utf8.count == 32)
        let accented = esclTruncatedName(String(repeating: "\u{E9}", count: 20))
        #expect(accented.utf8.count == 32 && accented.count == 16)
    }

    @Test func urlsAndPorts() {
        let c = ESCLClient(host: "fake", port: 80, transport: FakeESCLPrinter())
        #expect(c.baseURL.absoluteString == "http://fake/eSCL")
        #expect(c.absolute("/eSCL/ScanJobs/1/") == "http://fake/eSCL/ScanJobs/1")
        #expect(c.absolute("http://10.0.0.5/eSCL/ScanJobs/2") == "http://10.0.0.5/eSCL/ScanJobs/2")
        #expect(ESCLClient(host: "fake", port: 8081, transport: FakeESCLPrinter()).baseURL.absoluteString == "http://fake:8081/eSCL")
        #expect(ESCLClient.port(forRecorded: 8080) == 80)
        #expect(ESCLClient.port(forRecorded: 80) == 80)
    }
}

struct ESCLSessionFlowTests {
    private func start(_ printer: FakeESCLPrinter, sink: MemorySink) async -> (PrinterSession, Task<Void, Never>) {
        let prefs = ScanPreferences.defaults(deviceName: "Test Phone")
        let record = PrinterRecord(displayName: "Fake", host: "fake", port: 8080)
        let session = PrinterSession(printer: record, preferences: prefs, sink: sink, transport: printer)
        await session.setESCLPollInterval(.milliseconds(20))
        return (session, Task { await session.run() })
    }

    private func waitStatus(_ session: PrinterSession, _ pred: @escaping (SessionStatus) -> Bool) async -> Bool {
        let deadline = ContinuousClock.now + .seconds(5)
        while ContinuousClock.now < deadline {
            if pred(await session.lastStatus) { return true }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return false
    }

    private func isReady(_ s: SessionStatus) -> Bool {
        if case .ready(.escl, true) = s { return true }
        return false
    }

    @Test func fallsBackToESCLAndUnsubscribesOnStop() async {
        let printer = FakeESCLPrinter()
        let (session, task) = await start(printer, sink: MemorySink())
        #expect(await waitStatus(session, isReady))
        #expect(await printer.subscriptions == 1)
        task.cancel()
        _ = await task.value
        #expect(await printer.unsubscribes == 1)
    }

    @Test func flatbedPagesBecomeOnePDF() async {
        let printer = FakeESCLPrinter()
        let sink = MemorySink()
        let (session, task) = await start(printer, sink: sink)
        #expect(await waitStatus(session, isReady))
        await printer.push(ESCLFixtures.event("ScanRequested"))
        #expect(await waitStatus(session) { if case .waitingForMorePages(1) = $0 { return true }; return false })
        // The next page arrives as another ScanRequested, not ScanNewPageRequested.
        await printer.push(ESCLFixtures.event("ScanRequested"))
        #expect(await waitStatus(session) { if case .waitingForMorePages(2) = $0 { return true }; return false })
        await printer.push(ESCLFixtures.event("ScanPagesComplete"))
        let files = await sink.waitForFiles(1)
        #expect(files.count == 1)
        #expect(files.first.map { String(decoding: $0.data, as: UTF8.self).contains("/Count 2") } == true)
        let bodies = await printer.jobBodies
        #expect(bodies.count == 2)
        #expect(bodies.allSatisfy { $0.contains("<scan:ContextID>sub-1</scan:ContextID>") && !$0.contains("Duplex") })
        // Flatbed jobs stay open for the panel; deleting them would cancel it.
        #expect(await printer.jobDeletes == 0)
        let requests = await printer.requests
        #expect(!requests.contains { $0.contains("/eSCL/eSCL/") })
        task.cancel()
        _ = await task.value
    }

    @Test func feederRunIsOneDocument() async {
        let printer = FakeESCLPrinter()
        await printer.setAdfLoaded(true)
        let sink = MemorySink()
        let (session, task) = await start(printer, sink: sink)
        #expect(await waitStatus(session, isReady))
        await printer.push(ESCLFixtures.event("ScanRequested"))
        let files = await sink.waitForFiles(1)
        #expect(files.count == 1)
        #expect(files.first.map { String(decoding: $0.data, as: UTF8.self).contains("/Count 2") } == true)
        let bodies = await printer.jobBodies
        #expect(bodies.count == 1 && bodies[0].contains("<pwg:InputSource>Feeder</pwg:InputSource>"))
        #expect(await printer.jobDeletes == 1)
        task.cancel()
        _ = await task.value
    }

    @Test func jpegShortcutAndBusyScanner() async {
        let printer = FakeESCLPrinter()
        await printer.setBusyOnce(true)
        let sink = MemorySink()
        let (session, task) = await start(printer, sink: sink)
        #expect(await waitStatus(session, isReady))
        await printer.push(ESCLFixtures.event("ScanRequested", shortcut: "Save as JPEG", resolution: 600))
        let files = await sink.waitForFiles(1)
        #expect(files.count == 1 && files[0].name.hasSuffix(".jpg"))
        let bodies = await printer.jobBodies
        #expect(bodies.first?.contains("<scan:XResolution>600</scan:XResolution>") == true)
        task.cancel()
        _ = await task.value
    }

    @Test func vanishedSubscriptionRegistersAgain() async {
        let printer = FakeESCLPrinter()
        let (session, task) = await start(printer, sink: MemorySink())
        #expect(await waitStatus(session, isReady))
        await printer.setSubscriptionMissing(true)
        let deadline = ContinuousClock.now + .seconds(5)
        while await printer.subscriptions < 2, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(await printer.subscriptions == 2)
        task.cancel()
        _ = await task.value
    }
}
