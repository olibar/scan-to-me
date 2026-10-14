// UI state and the glue between the views and the printer sessions.
import Foundation
import ScanKit
import Observation
import os
import SwiftUI

@MainActor
@Observable
final class AppModel {
    private static let log = Logger(subsystem: "com.obarlier.scantome", category: "app")

    var printers: [PrinterRecord] = []
    var statuses: [UUID: SessionStatus] = [:]
    var log: [LogEntry] = []
    var recentScans: [SavedScan] = []
    var preferences: ScanPreferences
    var outputLocation: OutputLocation = .documents
    var wantsListening = false
    private(set) var isListening = false
    /// Last problem worth showing in the UI (bad folder, failed Photos save).
    var lastError: String?

    private struct RunningSession {
        let session: PrinterSession
        let runner: Task<Void, Never>
        let pump: Task<Void, Never>
    }

    private var sessions: [UUID: RunningSession] = [:]
    /// The resolved output folder; security-scoped access is held while it is set.
    private var outputFolder: (url: URL, scoped: Bool)?
    private let backgroundGuard = BackgroundTaskGuard()
    private var saveTask: Task<Void, Never>?

    init() {
        preferences = ScanPreferences.defaults(deviceName: UIDevice.current.name)
        if let state = Persistence.load() {
            printers = state.printers
            preferences = state.preferences
            outputLocation = state.outputLocation
            recentScans = state.recentScans
            wantsListening = state.wantsListening
        }
        resolveOutputFolder()
        Self.log.debug("app: loaded printers=\(self.printers.count) wantsListening=\(self.wantsListening)")
    }

    // MARK: - Listening

    func startListening() {
        guard !isListening else { return }
        guard let folder = outputFolder ?? resolveOutputFolder() else {
            lastError = "The output folder is not available. Choose another one in Settings."
            return
        }
        do {
            try preferences.validate()
        } catch {
            lastError = "\(error)"
            return
        }
        Self.log.debug("app: start listening printers=\(self.printers.count) folder=\(folder.url.path)")
        isListening = true
        wantsListening = true
        lastError = nil
        UIApplication.shared.isIdleTimerDisabled = true
        let sink = FolderScanSink(directory: folder.url, securityScoped: false)
        for printer in printers {
            start(printer: printer, sink: sink)
        }
        persist()
    }

    func stopListening(userInitiated: Bool = true) {
        guard isListening else { return }
        Self.log.debug("app: stop listening userInitiated=\(userInitiated)")
        for (_, running) in sessions {
            running.runner.cancel()
            running.pump.cancel()
        }
        sessions.removeAll()
        isListening = false
        if userInitiated { wantsListening = false }
        UIApplication.shared.isIdleTimerDisabled = false
        for id in statuses.keys { statuses[id] = .stopped }
        persist()
    }

    private func start(printer: PrinterRecord, sink: FolderScanSink) {
        let rediscover: PrinterSession.Rediscover = { record in
            guard let name = record.serviceName,
                  let found = await ScannerBrowser.find(serviceName: name),
                  let resolved = try? await EndpointResolver.resolve(found.endpoint) else { return nil }
            return (resolved.host, resolved.port)
        }
        let session = PrinterSession(printer: printer, preferences: preferences, sink: sink, rediscover: rediscover)
        statuses[printer.id] = .connecting
        let runner = Task { await session.run() }
        let pump = Task { [weak self] in
            for await event in session.events {
                guard let self else { return }
                await self.handle(event, from: printer.id)
            }
        }
        sessions[printer.id] = RunningSession(session: session, runner: runner, pump: pump)
    }

    private func handle(_ event: SessionEvent, from id: UUID) async {
        switch event {
        case let .status(s):
            statuses[id] = s
        case let .log(entry):
            log.append(entry)
            if log.count > 500 { log.removeFirst(log.count - 500) }
        case let .saved(scan):
            recentScans.insert(scan, at: 0)
            if recentScans.count > 50 { recentScans.removeLast(recentScans.count - 50) }
            persist()
            if scan.format == .jpeg, preferences.saveJPEGToPhotos {
                await saveToPhotos(scan)
            }
        case let .addressChanged(host, port):
            if let i = printers.firstIndex(where: { $0.id == id }) {
                Self.log.debug("app: printer \(self.printers[i].displayName) moved to \(host):\(port)")
                printers[i].host = host
                printers[i].port = port
                persist()
            }
        }
    }

    private func saveToPhotos(_ scan: SavedScan) async {
        do {
            let data = try Data(contentsOf: scan.url)
            try await PhotosSaver.save(jpeg: data)
            log.append(LogEntry(level: .info, printer: scan.printer, message: "added \(scan.url.lastPathComponent) to Photos"))
        } catch {
            Self.log.error("app: photos save failed: \(error)")
            lastError = "Could not add the scan to Photos: \(error.localizedDescription)"
            log.append(LogEntry(level: .error, printer: scan.printer, message: "Photos: \(error.localizedDescription)"))
        }
    }

    // MARK: - Scene phase

    func scenePhaseChanged(_ phase: ScenePhase) {
        Self.log.debug("app: scene phase \(String(describing: phase)) listening=\(self.isListening)")
        switch phase {
        case .background:
            guard isListening else { return }
            let running = Array(sessions.values)
            backgroundGuard.begin { [weak self] in
                self?.stopListening(userInitiated: false)
            }
            Task {
                for r in running where await r.session.isBusy {
                    await r.session.closeOpenDocument()
                }
                stopListening(userInitiated: false)
                backgroundGuard.end()
            }
        case .active:
            if wantsListening, !isListening, !printers.isEmpty { startListening() }
        default:
            break
        }
    }

    // MARK: - Printers

    func addPrinter(_ record: PrinterRecord) {
        guard !printers.contains(where: { $0.host == record.host && $0.port == record.port }) else { return }
        Self.log.debug("app: add printer \(record.displayName) \(record.address)")
        printers.append(record)
        persist()
        if isListening, let folder = outputFolder {
            start(printer: record, sink: FolderScanSink(directory: folder.url, securityScoped: false))
        }
    }

    func removePrinter(_ record: PrinterRecord) {
        Self.log.debug("app: remove printer \(record.displayName)")
        printers.removeAll { $0.id == record.id }
        if let running = sessions.removeValue(forKey: record.id) {
            running.runner.cancel()
            running.pump.cancel()
        }
        statuses[record.id] = nil
        persist()
    }

    // MARK: - Settings

    /// Called after any edit to `preferences`; restarts sessions so the new
    /// name and scan settings take effect.
    func preferencesChanged() {
        persist()
        guard isListening else { return }
        stopListening(userInitiated: false)
        startListening()
    }

    func setOutputLocation(_ location: OutputLocation) {
        Self.log.debug("app: output location -> \(location.displayName)")
        outputLocation = location
        releaseOutputFolder()
        resolveOutputFolder()
        persist()
        if isListening {
            stopListening(userInitiated: false)
            startListening()
        }
    }

    /// The folder scans are written to, if it can be reached right now.
    var currentOutputFolder: URL? { outputFolder?.url }

    @discardableResult
    private func resolveOutputFolder() -> (url: URL, scoped: Bool)? {
        do {
            let resolved = try outputLocation.resolve()
            if resolved.scoped, !resolved.url.startAccessingSecurityScopedResource() {
                throw OutputLocation.LocationError.accessDenied
            }
            if resolved.stale {
                Self.log.warning("app: bookmark for \(resolved.url.path) is stale, refreshing")
                if let data = try? resolved.url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    outputLocation = .bookmark(data, displayName: resolved.url.lastPathComponent)
                }
            }
            outputFolder = (resolved.url, resolved.scoped)
            return outputFolder
        } catch {
            Self.log.error("app: output folder unavailable: \(error)")
            lastError = "Output folder unavailable (\(error.localizedDescription)). Falling back to the app folder."
            outputLocation = .documents
            if let docs = try? OutputLocation.documents.resolve() {
                outputFolder = (docs.url, false)
                return outputFolder
            }
            return nil
        }
    }

    private func releaseOutputFolder() {
        if let folder = outputFolder, folder.scoped {
            folder.url.stopAccessingSecurityScopedResource()
        }
        outputFolder = nil
    }

    // MARK: - Persistence

    private func persist() {
        let state = PersistedState(printers: printers, preferences: preferences, outputLocation: outputLocation,
                                   recentScans: recentScans, wantsListening: wantsListening)
        saveTask?.cancel()
        saveTask = Task.detached(priority: .utility) {
            Persistence.save(state)
        }
    }
}
