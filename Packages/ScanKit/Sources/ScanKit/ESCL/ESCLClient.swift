// HTTP client for the eSCL scan interface (plain HTTP, default port, under
// /eSCL) offered by printers that no longer have LEDM. Covers the walkup
// subscription that puts this device on the panel, its event channel, and
// scan jobs that yield one or more pages.
//
//   POST   /eSCL/WalkupSubscriptions   register; 201 + Location
//   GET    <sub>/Event                 204 when idle, 200 with an event
//   POST   /eSCL/ScanJobs              start a scan; 201 + Location
//   GET    <job>/NextDocument          one page per call, 404 when done
//   DELETE <sub>                       unregister
import Foundation

/// A thin client bound to one printer's eSCL interface.
public struct ESCLClient: Sendable {
    /// e.g. http://192.168.1.10/eSCL
    public let baseURL: URL
    let transport: any HTTPTransport

    public init(host: String, port: Int, transport: (any HTTPTransport)? = nil) {
        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = EndpointResolver.stripScope(host.trimmingCharacters(in: .whitespaces))
        if port != 80 { comps.port = port }
        comps.path = "/eSCL"
        let base = comps.url ?? URL(string: "http://invalid-host/eSCL")!
        self.baseURL = base
        self.transport = transport ?? LEDMClient.makeSession()
        Log.escl.debug("escl: new client \(base.absoluteString)")
    }

    /// The eSCL port for a printer recorded with `port`. LEDM lives on 8080
    /// and eSCL never does; anything else is taken as given.
    public static func port(forRecorded port: Int) -> Int {
        port == 8080 ? 80 : port
    }

    struct Response: Sendable {
        var status: Int
        var body: Data
        var location: String?
    }

    // MARK: - Transport

    /// `path` is below /eSCL, or an absolute URL taken from a Location header.
    func request(_ method: String, _ path: String, body: Data? = nil, timeout: TimeInterval) async throws -> Response {
        let url = (path.hasPrefix("http://") || path.hasPrefix("https://") ? URL(string: path) : nil)
            ?? URL(string: baseURL.absoluteString + path) ?? baseURL
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        req.httpMethod = method
        req.httpBody = body
        if body != nil { req.setValue("text/xml", forHTTPHeaderField: "Content-Type") }
        Log.escl.debug("escl: request \(method) \(url.absoluteString) bodyBytes=\(body?.count ?? 0) timeout=\(timeout)")
        let start = ContinuousClock.now
        let (data, http) = try await transport.send(req)
        let r = Response(status: http.statusCode, body: data, location: http.value(forHTTPHeaderField: "Location"))
        Log.escl.debug("escl: response \(method) \(url.absoluteString) status=\(r.status) bodyBytes=\(data.count) location=\(r.location ?? "-") elapsed=\(ContinuousClock.now - start)")
        return r
    }

    func get(_ path: String, timeout: TimeInterval = 20) async throws -> Response {
        let r = try await request("GET", path, timeout: timeout)
        guard (200...299).contains(r.status) else { throw statusError("GET", path, r) }
        return r
    }

    private func statusError(_ method: String, _ path: String, _ r: Response) -> LEDMError {
        .status(method: method, path: path, status: r.status, body: String(decoding: r.body, as: UTF8.self))
    }

    /// Turns a Location header into an absolute URL. Printers answer with a
    /// full URL or a server-absolute path ("/eSCL/ScanJobs/1"); joining the
    /// latter to baseURL naively would give /eSCL/eSCL/...
    func absolute(_ location: String) -> String {
        let trimmed = location.hasSuffix("/") ? String(location.dropLast()) : location
        return URL(string: trimmed, relativeTo: baseURL)?.absoluteString ?? trimmed
    }

    // MARK: - Scanner

    /// True when the host answers on the eSCL interface.
    public func probe() async -> Bool {
        do {
            _ = try await get("/ScannerStatus", timeout: 5)
            return true
        } catch {
            Log.escl.debug("escl: probe failed \(self.baseURL.absoluteString): \(error)")
            return false
        }
    }

    public func capabilities() async throws -> ESCLCaps {
        try ESCLCaps.parse(try await get("/ScannerCapabilities").body)
    }

    public func status() async throws -> ESCLStatus {
        try ESCLStatus.parse(try await get("/ScannerStatus").body)
    }

    /// Polls the scanner until it is idle or the timeout elapses.
    public func waitIdle(timeout: Duration) async throws -> ESCLStatus {
        let deadline = ContinuousClock.now + timeout
        while true {
            let st = try await status()
            if st.isIdle { return st }
            Log.escl.debug("escl: scanner busy (\(st.state)), waiting")
            if ContinuousClock.now >= deadline {
                throw LEDMError.timeout("scanner still \(st.state) after \(timeout)")
            }
            try await Task.sleep(for: .seconds(1))
        }
    }

    // MARK: - Walkup subscription

    /// Registers this device on the panel and returns the subscription URL.
    /// The printer lists it only while its Event resource is being polled.
    public func subscribe(name: String) async throws -> String {
        let path = "/WalkupSubscriptions"
        let body = Data(registrationXML(.escl, name: name, hostname: name).utf8)
        let r = try await request("POST", path, body: body, timeout: 20)
        guard r.status == 201 || r.status == 200 else { throw statusError("POST", path, r) }
        guard let loc = r.location, !loc.isEmpty else {
            throw LEDMError.missingLocation("walkup subscription (http \(r.status))")
        }
        let uri = absolute(loc)
        Log.escl.info("escl: subscribed name=\(name) uri=\(uri)")
        return uri
    }

    /// Removes the subscription; 404 counts as success.
    public func unsubscribe(_ uri: String) async throws {
        let r = try await request("DELETE", uri, timeout: 10)
        guard r.status == 200 || r.status == 204 || r.status == 404 else { throw statusError("DELETE", uri, r) }
        Log.escl.debug("escl: unsubscribed uri=\(uri) status=\(r.status)")
    }

    /// Reads the next panel instruction, nil when there is none. The resource
    /// does not long-poll: it answers 204 at once, so the caller paces calls.
    /// A request abandoned mid-flight leaves the subscription answering 503
    /// until it is recreated, hence a deadline well above the reply time.
    public func nextEvent(subscription uri: String) async throws -> WalkupEvent? {
        let path = uri + "/Event"
        let r = try await request("GET", path, timeout: 30)
        if r.status == 204 { return nil }
        guard (200...299).contains(r.status) else { throw statusError("GET", path, r) }
        if r.body.allSatisfy({ $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }) { return nil }
        return try WalkupEvent.parse(r.body)
    }

    // MARK: - Scanning

    /// Runs one scan job and returns its pages as JPEG bytes. The flatbed
    /// yields one page and the job is left open: the panel asks the user
    /// about another page and sends a fresh event. A feeder job is read to
    /// the end and then released.
    func scanPages(_ settings: ESCLScanSettings) async throws -> [Data] {
        Log.escl.info("escl: starting scan source=\(settings.isFeeder ? "Feeder" : "Platen") resolution=\(settings.base.resolution) size=\(settings.base.width)x\(settings.base.height) color=\(settings.base.color) duplex=\(settings.duplex)")
        let job = try await createJob(settings)
        var pages: [Data] = []
        while true {
            let page: Data?
            do {
                page = try await nextDocument(job)
            } catch {
                if pages.isEmpty { throw error }
                Log.escl.warning("escl: scan interrupted, keeping \(pages.count) pages job=\(job): \(error)")
                return pages
            }
            guard let page else {
                // A finished job: deleting it is a harmless tidy-up. Deleting
                // an open flatbed job would cancel the panel session instead.
                _ = try? await request("DELETE", job, timeout: 10)
                break
            }
            pages.append(page)
            Log.escl.info("escl: page received page=\(pages.count) bytes=\(page.count)")
            if !settings.isFeeder { break }
        }
        guard !pages.isEmpty else { throw LEDMError.noPages(state: "no document in job \(job)") }
        Log.escl.info("escl: scan finished job=\(job) pages=\(pages.count)")
        return pages
    }

    /// Creates the job, posting again while the scanner answers 503: it does
    /// that routinely while finishing the previous page of a walkup scan.
    private func createJob(_ settings: ESCLScanSettings) async throws -> String {
        let body = Data(settings.xml().utf8)
        var attempt = 0
        while true {
            let r = try await request("POST", "/ScanJobs", body: body, timeout: 30)
            if r.status == 503, attempt < 5 {
                attempt += 1
                Log.escl.debug("escl: scanner busy, posting the job again attempt=\(attempt)")
                try await Task.sleep(for: .milliseconds(700))
                continue
            }
            guard r.status == 201 || r.status == 200 else { throw statusError("POST", "/ScanJobs", r) }
            guard let loc = r.location, !loc.isEmpty else {
                throw LEDMError.missingLocation("create scan job (http \(r.status))")
            }
            let job = absolute(loc)
            Log.escl.debug("escl: scan job created \(job)")
            return job
        }
    }

    /// One page, or nil when the job has none left (404, 410 or an empty
    /// 200 depending on firmware). 503 means the page is still being made.
    private func nextDocument(_ job: String) async throws -> Data? {
        let path = job + "/NextDocument"
        let deadline = ContinuousClock.now + .seconds(300)
        while true {
            let r = try await request("GET", path, timeout: 240)
            switch r.status {
            case 404, 410:
                return nil
            case 503 where ContinuousClock.now < deadline:
                Log.escl.debug("escl: page not ready, retrying")
                try await Task.sleep(for: .milliseconds(500))
            case 200...299:
                return r.body.isEmpty ? nil : r.body
            default:
                throw statusError("GET", path, r)
            }
        }
    }
}
