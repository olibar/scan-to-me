// HTTP client for the HP "Low End Data Model" REST interface exposed on
// port 8080 (80 on some models). Covers what Scan-to-Computer needs:
// discovery, destination registration, event polling and scan jobs.
import Foundation

/// A thin client bound to one printer.
public struct LEDMClient: Sendable {
    public let baseURL: URL
    let transport: any HTTPTransport

    public init(host: String, port: Int, transport: (any HTTPTransport)? = nil) {
        // Addresses stored before the scope fix may still carry "%en0".
        let host = EndpointResolver.stripScope(host.trimmingCharacters(in: .whitespaces))
        var comps = URLComponents()
        comps.scheme = "http"
        comps.host = host
        comps.port = port
        let base = comps.url ?? URL(string: "http://\(host):\(port)") ?? URL(string: "http://invalid-host:\(port)")!
        self.baseURL = base
        self.transport = transport ?? LEDMClient.makeSession()
        Log.ledm.debug("ledm: new client \(base.absoluteString)")
    }

    /// A session tuned for the printer: no cache (the printer's 304 replies
    /// must reach us untouched or the long-poll degenerates into a hot loop),
    /// long inactivity timeout as a safety net behind per-request deadlines.
    public static func makeSession() -> URLSession {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.urlCache = nil
        cfg.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        cfg.timeoutIntervalForRequest = 300
        cfg.timeoutIntervalForResource = 600
        cfg.waitsForConnectivity = false
        cfg.httpMaximumConnectionsPerHost = 2
        cfg.httpShouldSetCookies = false
        return URLSession(configuration: cfg)
    }

    struct Response: Sendable {
        var status: Int
        var body: Data
        var location: String?
        var etag: String?
        var contentType: String?
    }

    // MARK: - Transport

    func request(_ method: String, _ path: String, body: Data? = nil,
                 headers: [String: String] = [:], timeout: TimeInterval) async throws -> Response {
        let url: URL
        if path.hasPrefix("http://") || path.hasPrefix("https://"), let abs = URL(string: path) {
            url = abs
        } else {
            url = URL(string: path, relativeTo: baseURL)?.absoluteURL ?? baseURL.appendingPathComponent(path)
        }
        var req = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: timeout)
        req.httpMethod = method
        req.httpBody = body
        if body != nil { req.setValue("text/xml", forHTTPHeaderField: "Content-Type") }
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        Log.ledm.debug("ledm: request \(method) \(url.absoluteString) bodyBytes=\(body?.count ?? 0) timeout=\(timeout)")
        let start = ContinuousClock.now
        let (data, http) = try await transport.send(req)
        let r = Response(status: http.statusCode, body: data,
                         location: http.value(forHTTPHeaderField: "Location"),
                         etag: http.value(forHTTPHeaderField: "ETag"),
                         contentType: http.value(forHTTPHeaderField: "Content-Type"))
        let elapsed = ContinuousClock.now - start
        Log.ledm.debug("ledm: response \(method) \(url.absoluteString) status=\(r.status) bodyBytes=\(data.count) location=\(r.location ?? "-") etag=\(r.etag ?? "-") elapsed=\(elapsed)")
        return r
    }

    /// GET with a default deadline, failing on non-2xx.
    func get(_ path: String, timeout: TimeInterval = 20) async throws -> Response {
        let r = try await request("GET", path, timeout: timeout)
        guard (200...299).contains(r.status) else {
            throw LEDMError.status(method: "GET", path: path, status: r.status, body: String(decoding: r.body, as: UTF8.self))
        }
        return r
    }

    /// Raw GET used by troubleshooting tools.
    public func fetch(_ path: String) async throws -> (Data, Int) {
        let r = try await request("GET", path, timeout: 20)
        return (r.body, r.status)
    }

    // MARK: - Discovery and capabilities

    public func discover() async throws -> Capabilities {
        let r = try await get("/DevMgmt/DiscoveryTree.xml")
        return try Capabilities.parse(r.body)
    }

    public func scanCaps() async throws -> ScanCaps {
        let r = try await get("/Scan/ScanCaps")
        return try ScanCaps.parse(r.body)
    }

    public func status() async throws -> ScanStatus {
        let r = try await get("/Scan/Status")
        return try ScanStatus.parse(r.body)
    }

    /// Polls /Scan/Status until the scanner is idle or the timeout elapses.
    public func waitIdle(timeout: Duration) async throws -> ScanStatus {
        let deadline = ContinuousClock.now + timeout
        while true {
            let st = try await status()
            if st.isIdle { return st }
            Log.ledm.debug("ledm: scanner busy (\(st.scannerState)), waiting")
            if ContinuousClock.now >= deadline {
                throw LEDMError.timeout("scanner still \(st.scannerState) after \(timeout)")
            }
            try await Task.sleep(for: .seconds(1))
        }
    }

    // MARK: - Destinations

    /// Registers this device and returns the destination URI.
    public func registerDestination(_ flavor: WalkupFlavor, name: String, hostname: String) async throws -> String {
        Log.ledm.debug("ledm: register destination flavor=\(flavor.rawValue) name=\(name)")
        let body = Data(registrationXML(flavor, name: name, hostname: hostname).utf8)
        let path = flavor.destinationsPath
        let r = try await request("POST", path, body: body, timeout: 20)
        guard r.status == 201 || r.status == 200 else {
            throw LEDMError.status(method: "POST", path: path, status: r.status, body: String(decoding: r.body, as: UTF8.self))
        }
        guard let loc = r.location, !loc.isEmpty else {
            throw LEDMError.missingLocation("register destination (http \(r.status))")
        }
        let uri = locationPath(loc)
        Log.ledm.info("ledm: destination registered flavor=\(flavor.rawValue) name=\(name) uri=\(uri)")
        return uri
    }

    /// Reads one destination, including the shortcut picked on the panel.
    public func destination(at uri: String) async throws -> Destination {
        let r = try await get(uri)
        return try Destination.parse(r.body, uri: uri)
    }

    /// Removes a destination; 404 counts as success.
    public func deleteDestination(at uri: String) async throws {
        let r = try await request("DELETE", uri, timeout: 20)
        guard r.status == 200 || r.status == 204 || r.status == 404 else {
            throw LEDMError.status(method: "DELETE", path: uri, status: r.status, body: String(decoding: r.body, as: UTF8.self))
        }
        Log.ledm.debug("ledm: destination deleted uri=\(uri) status=\(r.status)")
    }

    // MARK: - Events

    /// Fetches the event table. With a previous ETag the request long-polls
    /// up to `waitSeconds` and reports `changed == false` on 304.
    public func pollEvents(previous: EventTable, waitSeconds: Int) async throws -> (table: EventTable, changed: Bool) {
        var path = "/EventMgmt/EventTable"
        var headers: [String: String] = [:]
        if let etag = previous.etag, !etag.isEmpty {
            path = "/EventMgmt/EventTable?timeout=\(waitSeconds)"
            headers["If-None-Match"] = etag
        }
        let r = try await request("GET", path, headers: headers, timeout: TimeInterval(waitSeconds + 30))
        if r.status == 304 {
            Log.ledm.debug("ledm: event table unchanged")
            return (previous, false)
        }
        guard (200...299).contains(r.status) else {
            throw LEDMError.status(method: "GET", path: path, status: r.status, body: String(decoding: r.body, as: UTF8.self))
        }
        return (try EventTable.parse(r.body, etag: r.etag), true)
    }

    /// Reads why the last ScanEvent fired.
    public func compEvent() async throws -> CompEventType {
        let r = try await get("/WalkupScanToComp/WalkupScanToCompEvent")
        return try CompEventType.parse(r.body)
    }

    // MARK: - Scanning

    /// Runs one scan job and returns every page it produced as JPEG bytes:
    /// one for the flatbed, one per sheet for the document feeder.
    public func scanPages(_ settings: ScanSettings) async throws -> [Data] {
        Log.ledm.info("ledm: starting scan source=\(settings.source.rawValue) resolution=\(settings.resolution) size=\(settings.width)x\(settings.height) color=\(settings.color)")
        let jobURL = try await createJob(settings)
        var pages: [Data] = []
        var got = Set<Int>()
        var deadline = ContinuousClock.now + .seconds(300)
        while ContinuousClock.now < deadline {
            let job = try await getJob(jobURL)
            for p in job.pre {
                guard !got.contains(p.number), p.state.caseInsensitiveCompare("ReadyToUpload") == .orderedSame,
                      let url = p.binaryURL, !url.isEmpty else { continue }
                let img = try await download(url)
                got.insert(p.number)
                pages.append(img)
                deadline = ContinuousClock.now + .seconds(300)
                Log.ledm.info("ledm: page received page=\(p.number) bytes=\(img.count)")
            }
            if jobFinished(job, source: settings.source, pages: pages.count) {
                guard !pages.isEmpty else { throw LEDMError.noPages(state: job.state) }
                Log.ledm.info("ledm: scan finished job=\(jobURL) state=\(job.state) pages=\(pages.count)")
                return pages
            }
            try await Task.sleep(for: .milliseconds(700))
        }
        if !pages.isEmpty {
            Log.ledm.warning("ledm: scan job never reported completion, keeping \(pages.count) pages job=\(jobURL)")
            return pages
        }
        throw LEDMError.timeout("scan job \(jobURL) did not finish within 5 minutes")
    }

    private func createJob(_ settings: ScanSettings) async throws -> String {
        let r = try await request("POST", "/Scan/Jobs", body: Data(settings.xml().utf8), timeout: 30)
        guard r.status == 201 || r.status == 200 else {
            throw LEDMError.status(method: "POST", path: "/Scan/Jobs", status: r.status, body: String(decoding: r.body, as: UTF8.self))
        }
        guard let loc = r.location, !loc.isEmpty else {
            throw LEDMError.missingLocation("create scan job (http \(r.status))")
        }
        Log.ledm.debug("ledm: scan job created \(loc)")
        return loc
    }

    private func getJob(_ url: String) async throws -> JobStatus {
        let r = try await get(url)
        return try JobStatus.parse(r.body)
    }

    private func download(_ url: String) async throws -> Data {
        Log.ledm.debug("ledm: downloading page \(url)")
        let r = try await request("GET", url, timeout: 240)
        guard (200...299).contains(r.status) else {
            throw LEDMError.status(method: "GET", path: url, status: r.status, body: String(decoding: r.body, as: UTF8.self))
        }
        Log.ledm.debug("ledm: page downloaded bytes=\(r.body.count) contentType=\(r.contentType ?? "-")")
        return r.body
    }
}
