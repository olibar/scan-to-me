// The eSCL half of the session, for printers that dropped LEDM: same job as
// the LEDM loop, different registration, events and scan jobs. Documents,
// PDF assembly and file naming are shared with the LEDM path.
import Foundation

extension PrinterSession {
    /// What the poller and the ticker hand to the session loop.
    enum ESCLSignal: Sendable {
        case event(WalkupEvent)
        case tick
        case failed(any Error)
    }

    /// Switches to eSCL when the printer answers there. False leaves the LEDM
    /// error standing (the printer is unreachable or speaks neither).
    func useESCL(because ledmError: any Error) async throws -> Bool {
        let host = URLComponents(url: client.baseURL, resolvingAgainstBaseURL: false)?.host ?? printer.host
        let recorded = client.baseURL.port ?? 80
        guard let candidate = await ESCLClient.locate(host: host, recordedPort: recorded, transport: transport) else {
            Log.session.debug("session: no eSCL interface at \(host) on \(ESCLClient.candidatePorts(forRecorded: recorded)) either")
            return false
        }
        log(.info, "no usable LEDM interface (\(ledmError)), using eSCL at \(candidate.baseURL.absoluteString)")
        escl = candidate
        flavor = .escl
        esclCaps = try await candidate.capabilities()
        caps = esclCaps.scanCaps
        try await esclRegister()
        return true
    }

    /// Puts this device on the panel under the destination name.
    func esclRegister() async throws {
        guard let escl else { return }
        let name = esclTruncatedName(preferences.destinationName)
        destinationURI = try await escl.subscribe(name: name)
        log(.info, "ready as \"\(name)\" (eSCL, \(esclCaps.makeAndModel), feeder: \(esclCaps.scanCaps.hasAdf))")
        emitReady()
    }

    /// Handles panel events until cancelled. Polling runs in its own task:
    /// it is also how the printer knows this device is still there, and a
    /// scan takes long enough that pausing it would make the panel report
    /// that the file could not be saved.
    func esclLoop(_ escl: ESCLClient) async throws {
        let (signals, out) = AsyncStream.makeStream(of: ESCLSignal.self)
        let poller = Task { await self.esclPoll(escl, out) }
        let ticker = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                out.yield(.tick)
            }
        }
        defer {
            poller.cancel()
            ticker.cancel()
            out.finish()
        }
        for await signal in signals {
            try Task.checkCancellation()
            switch signal {
            case let .event(ev): await onESCLEvent(ev, escl)
            case .tick: await expireDocument()
            case let .failed(error): throw error
            }
        }
        try Task.checkCancellation()
    }

    /// Reads events at the pace the printer expects, re-registering when the
    /// subscription vanishes (printer reboot, or evicted for another host).
    private func esclPoll(_ escl: ESCLClient, _ out: AsyncStream<ESCLSignal>.Continuation) async {
        var failures = 0
        while !Task.isCancelled {
            do {
                let event = try await escl.nextEvent(subscription: destinationURI)
                failures = 0
                if let event {
                    out.yield(.event(event))
                } else {
                    try await Task.sleep(for: esclPollInterval)
                }
            } catch is CancellationError {
                return
            } catch let error as LEDMError where error.isNotFound {
                log(.warning, "subscription vanished (printer reboot?), registering again")
                do {
                    try await esclRegister()
                } catch {
                    out.yield(.failed(error))
                    return
                }
            } catch {
                if Task.isCancelled { return }
                failures += 1
                log(.warning, "event poll failed (\(failures)/5): \(error)")
                if failures >= 5 {
                    out.yield(.failed(LEDMError.timeout("event polling failed \(failures) times: \(error)")))
                    return
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
    }

    private func onESCLEvent(_ ev: WalkupEvent, _ escl: ESCLClient) async {
        log(.info, "walkup event \(ev.type.rawType) shortcut=\(ev.shortcut)")
        switch ev.type {
        case .scanRequested, .scanNewPageRequested:
            // Each extra flatbed page arrives as another ScanRequested; only
            // ScanPagesComplete ends the document, so neither closes it here.
            do {
                try await esclScan(ev, escl)
            } catch is CancellationError {
                return
            } catch {
                log(.error, "scan event handling failed: \(error)")
                emitReady()
            }
        case .scanPagesComplete:
            await finishDocument()
            jpegPage = 0
            emitReady()
        case .hostSelected:
            break // the user is browsing the shortcut menu
        case let .unknown(raw):
            log(.warning, "unknown walkup event type \(raw)")
        }
    }

    /// Scans from the feeder when it reports paper, the flatbed otherwise,
    /// with what the user chose on the panel winning over the preferences.
    private func esclScan(_ ev: WalkupEvent, _ escl: ESCLClient) async throws {
        scanning = true
        defer { scanning = false }
        emit(.status(.scanning(pagesSoFar: document?.pages.count ?? 0)))
        let status = try await escl.waitIdle(timeout: .seconds(60))
        let useAdf = esclCaps.scanCaps.hasAdf && esclCaps.detectsPaperLoaded && status.paperLoaded
        var settings = ESCLScanSettings(base: preferences.scanSettings(for: useAdf ? .adf : .platen, caps: caps))
        if ev.resolution > 0 { settings.base.resolution = ev.resolution }
        settings.duplex = useAdf && ev.duplex && esclCaps.hasAdfDuplex
        settings.contextID = destinationURI.split(separator: "/").last.map(String.init) ?? ""
        settings.machineName = esclTruncatedName(preferences.destinationName)
        let pages = try await escl.scanPages(settings)
        try await store(pages, format: preferences.format(forShortcut: ev.shortcut),
                        dpi: settings.base.resolution, single: useAdf, trim: preferences.trimMargins && !useAdf)
    }
}
