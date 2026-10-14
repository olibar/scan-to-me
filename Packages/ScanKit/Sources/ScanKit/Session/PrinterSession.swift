// The scan-to-computer loop for one printer: register as a destination, wait
// for the user to press Scan on the panel, fetch the page(s) and hand them
// to the sink. Reconnects with backoff until the task is cancelled.
import Foundation

public actor PrinterSession {
    /// Finds the printer again when its address stops answering. Returns nil
    /// when it is not on the network.
    public typealias Rediscover = @Sendable (PrinterRecord) async -> (host: String, port: Int)?

    public let printer: PrinterRecord
    public let preferences: ScanPreferences
    public nonisolated let events: AsyncStream<SessionEvent>

    private let sink: any ScanSink
    private let transport: (any HTTPTransport)?
    private let rediscover: Rediscover?
    private let continuation: AsyncStream<SessionEvent>.Continuation

    private var client: LEDMClient
    private var flavor: WalkupFlavor = .walkupScanToComp
    private var destinationURI = ""
    private var caps: ScanCaps?
    private var tracker = EventTracker()
    private var document: ScanDocument?
    private var jpegPage = 0
    private var scanning = false
    /// Most recent status, also delivered through `events`.
    public private(set) var lastStatus: SessionStatus = .connecting

    public init(printer: PrinterRecord, preferences: ScanPreferences, sink: any ScanSink,
                transport: (any HTTPTransport)? = nil, rediscover: Rediscover? = nil) {
        self.printer = printer
        self.preferences = preferences
        self.sink = sink
        self.transport = transport
        self.rediscover = rediscover
        self.client = LEDMClient(host: printer.host, port: printer.port, transport: transport)
        var cont: AsyncStream<SessionEvent>.Continuation!
        self.events = AsyncStream(bufferingPolicy: .bufferingNewest(200)) { cont = $0 }
        self.continuation = cont
    }

    /// A scan job is in flight or a multi-page PDF is open.
    public var isBusy: Bool { scanning || document != nil }

    /// Writes the open PDF with the pages received so far (used before the
    /// app is suspended).
    public func closeOpenDocument() async {
        await finishDocument()
    }

    // MARK: - Main loop

    /// Runs until the surrounding task is cancelled.
    public func run() async {
        var backoff: Duration = .seconds(5)
        defer {
            emit(.status(.stopped))
            continuation.finish()
        }
        while !Task.isCancelled {
            emit(.status(.connecting))
            let started = ContinuousClock.now
            do {
                try await runOnce()
            } catch is CancellationError {
                return
            } catch {
                if Task.isCancelled { return }
                if ContinuousClock.now - started > .seconds(60) { backoff = .seconds(5) }
                log(.error, "session ended, reconnecting in \(backoff): \(error)")
                emit(.status(.error("\(error)")))
                do { try await Task.sleep(for: backoff) } catch { return }
                if backoff < .seconds(60) { backoff *= 2 }
                continue
            }
        }
    }

    private func runOnce() async throws {
        client = LEDMClient(host: printer.host, port: printer.port, transport: transport)
        do {
            try await setup()
        } catch {
            try Task.checkCancellation()
            guard let rediscover, printer.serviceName != nil else { throw error }
            log(.warning, "printer unreachable at \(printer.address), looking it up via Bonjour: \(error)")
            guard let found = await rediscover(printer) else {
                throw LEDMError.timeout("printer \(printer.displayName) not found via Bonjour")
            }
            log(.info, "printer found at \(found.host):\(found.port)")
            emit(.addressChanged(host: found.host, port: found.port))
            client = LEDMClient(host: found.host, port: found.port, transport: transport)
            try await setup()
        }
        do {
            try await loop()
        } catch {
            await teardown()
            throw error
        }
        await teardown()
    }

    private func setup() async throws {
        let capabilities = try await client.discover()
        if capabilities.walkupScanToComp {
            flavor = .walkupScanToComp
        } else if capabilities.walkupScan {
            flavor = .walkupScan
        } else {
            throw LEDMError.unsupportedPrinter(resources: capabilities.resources)
        }
        if !capabilities.eventTable {
            log(.warning, "printer did not advertise /EventMgmt, trying anyway")
        }
        do {
            caps = try await client.scanCaps()
        } catch {
            log(.warning, "could not read scan caps, using paper size as-is: \(error)")
        }
        try await register()
    }

    private func register() async throws {
        let name = preferences.destinationName
        destinationURI = try await client.registerDestination(flavor, name: name, hostname: name)
        let hasAdf = caps?.hasAdf ?? false
        log(.info, "ready as \"\(name)\" (\(flavor.rawValue), feeder: \(hasAdf))")
        emit(.status(.ready(flavor: flavor, hasAdf: hasAdf)))
    }

    /// Unregisters and closes the open document. Runs detached because a
    /// cancelled task cannot issue URLSession calls any more.
    private func teardown() async {
        await finishDocument()
        guard !destinationURI.isEmpty else { return }
        let client = self.client
        let uri = destinationURI
        destinationURI = ""
        await Task.detached {
            do {
                try await client.deleteDestination(at: uri)
            } catch {
                Log.session.debug("session: unregister failed: \(error)")
            }
        }.value
    }

    private func loop() async throws {
        var (table, _) = try await client.pollEvents(previous: EventTable(), waitSeconds: 0)
        tracker.prime(with: table)
        var failures = 0
        while true {
            try Task.checkCancellation()
            do {
                let (next, changed) = try await client.pollEvents(previous: table, waitSeconds: 20)
                failures = 0
                table = next
                if changed {
                    await handleEvents(table.events)
                } else {
                    try await Task.sleep(for: .seconds(1))
                }
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                failures += 1
                log(.warning, "event poll failed (\(failures)/5): \(error)")
                if failures >= 5 {
                    throw LEDMError.timeout("event polling failed \(failures) times: \(error)")
                }
                try await Task.sleep(for: .seconds(3))
            }
            await expireDocument()
        }
    }

    // MARK: - Events

    private func handleEvents(_ events: [Event]) async {
        for e in tracker.unseen(in: events) {
            Log.session.debug("session: new event category=\(e.category) stamp=\(e.agingStamp) payloads=\(e.payloads.count)")
            guard e.category == "ScanEvent" else { continue }
            guard EventTracker.isForMe(e, destinationURI: destinationURI) else {
                Log.session.debug("session: scan event for another destination, ignoring")
                continue
            }
            do {
                try await onScanEvent()
            } catch is CancellationError {
                return
            } catch {
                log(.error, "scan event handling failed: \(error)")
                emit(.status(.ready(flavor: flavor, hasAdf: caps?.hasAdf ?? false)))
            }
        }
    }

    private func onScanEvent() async throws {
        let dst: Destination
        do {
            dst = try await client.destination(at: destinationURI)
        } catch let e as LEDMError where e.isNotFound {
            log(.warning, "destination vanished (printer reboot?), re-registering")
            try await register()
            return
        }
        if flavor == .walkupScan {
            try await scanPage(destination: dst, single: true)
            return
        }
        let type = try await client.compEvent()
        log(.info, "walkup event \(type.rawType) shortcut=\(dst.shortcut)")
        switch type {
        case .scanRequested:
            await finishDocument()
            jpegPage = 0
            try await scanPage(destination: dst, single: false)
        case .scanNewPageRequested:
            try await scanPage(destination: dst, single: false)
        case .scanPagesComplete:
            await finishDocument()
            jpegPage = 0
            emit(.status(.ready(flavor: flavor, hasAdf: caps?.hasAdf ?? false)))
        case .hostSelected:
            break // the user is browsing the shortcut menu
        case let .unknown(raw):
            log(.warning, "unknown walkup event type \(raw)")
        }
    }

    // MARK: - Scanning

    /// Scans from the flatbed, or from the feeder when it has paper, then
    /// writes JPEG pages or appends to the current PDF document.
    private func scanPage(destination: Destination, single: Bool) async throws {
        let format = preferences.format(forShortcut: destination.shortcut)
        scanning = true
        defer { scanning = false }
        emit(.status(.scanning(pagesSoFar: document?.pages.count ?? 0)))
        let status = try await client.waitIdle(timeout: .seconds(60))
        let useAdf = (caps?.hasAdf ?? false) && status.adfLoaded
        let settings = preferences.scanSettings(for: useAdf ? .adf : .platen, caps: caps)
        let pages = try await client.scanPages(settings)
        var single = single
        if settings.source == .adf { single = true } // a feeder run is a complete document
        if format == .jpeg {
            for img in pages {
                jpegPage += 1
                let base = FilenamePattern.render(preferences.filenamePattern, date: Date(), page: jpegPage)
                let url = try await sink.write(img, baseName: base, ext: "jpg")
                log(.info, "saved \(url.lastPathComponent) (\(img.count) bytes)")
                emit(.saved(SavedScan(url: url, pages: 1, format: .jpeg, printer: printer.displayName)))
            }
            if single { jpegPage = 0 }
            emit(.status(.ready(flavor: flavor, hasAdf: caps?.hasAdf ?? false)))
            return
        }
        var doc = document ?? ScanDocument()
        for img in pages {
            doc.pages.append(PDFWriter.Page(jpeg: img, dpi: settings.resolution))
        }
        doc.lastPage = Date()
        document = doc
        log(.info, "pages captured: \(pages.count) new, \(doc.pages.count) total")
        if single {
            await finishDocument()
            emit(.status(.ready(flavor: flavor, hasAdf: caps?.hasAdf ?? false)))
        } else {
            emit(.status(.waitingForMorePages(pages: doc.pages.count)))
        }
    }

    /// Closes a PDF that received no page for `pageTimeout` (the printer never
    /// sent ScanPagesComplete).
    private func expireDocument() async {
        guard let doc = document, doc.isExpired(now: Date(), timeout: preferences.pageTimeout) else { return }
        log(.info, "no further pages, closing document with \(doc.pages.count) pages")
        await finishDocument()
        emit(.status(.ready(flavor: flavor, hasAdf: caps?.hasAdf ?? false)))
    }

    private func finishDocument() async {
        guard let doc = document else { return }
        document = nil
        guard !doc.pages.isEmpty else { return }
        do {
            let pdf = try PDFWriter.write(doc.pages)
            let base = FilenamePattern.render(preferences.filenamePattern, date: Date(), page: 0)
            let url = try await sink.write(pdf, baseName: base, ext: "pdf")
            log(.info, "saved \(url.lastPathComponent) (\(doc.pages.count) pages)")
            emit(.saved(SavedScan(url: url, pages: doc.pages.count, format: .pdf, printer: printer.displayName)))
        } catch {
            log(.error, "saving PDF failed: \(error)")
        }
    }

    // MARK: - Reporting

    private func emit(_ event: SessionEvent) {
        if case let .status(s) = event { lastStatus = s }
        continuation.yield(event)
    }

    private func log(_ level: LogEntry.Level, _ message: String) {
        let name = printer.displayName
        switch level {
        case .debug: Log.session.debug("session[\(name)]: \(message)")
        case .info: Log.session.info("session[\(name)]: \(message)")
        case .warning: Log.session.warning("session[\(name)]: \(message)")
        case .error: Log.session.error("session[\(name)]: \(message)")
        }
        emit(.log(LogEntry(level: level, printer: name, message: message)))
    }
}
