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
    /// Whether each printer is on the current network; missing while the
    /// first check runs. Printers with a running session report through it.
    var presence: [UUID: Bool] = [:]
    var log: [LogEntry] = []
    var recentScans: [SavedScan] = []
    var preferences: ScanPreferences
    var outputLocation: OutputLocation = .documents
    var wantsListening = false
    private(set) var isListening = false
    /// Last problem worth showing in the UI (bad folder, failed Photos save).
    var lastError: String?
    /// Set while the chosen folder cannot be opened; scans go to the app
    /// folder meanwhile and the choice is kept so it can recover.
    private(set) var folderProblem: String?

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
    /// Pending restart after a settings edit; replaced by each new edit.
    private var restartTask: Task<Void, Never>?
    /// Periodic presence check, running while the app is in the foreground.
    private var presenceTask: Task<Void, Never>?

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
        // Retry a chosen folder that could not be opened last time (iCloud not
        // signed in yet, provider app updating...).
        if outputFolder == nil || folderProblem != nil {
            releaseOutputFolder()
            resolveOutputFolder()
        }
        guard let folder = outputFolder else {
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
        // Bonjour printers start once they are seen on this network, so an
        // identical printer at another site is never contacted by mistake.
        for printer in printers where !printer.isBonjour || presence[printer.id] == true {
            start(printer: printer, folder: folder.url)
        }
        persist()
        Task { await refreshPresence() }
    }

    /// Cancels every session and returns their runners, which finish once
    /// the session has unregistered from its printer.
    @discardableResult
    func stopListening(userInitiated: Bool = true) -> [Task<Void, Never>] {
        guard isListening else { return [] }
        Self.log.debug("app: stop listening userInitiated=\(userInitiated)")
        if userInitiated { restartTask?.cancel() }
        for (_, running) in sessions {
            running.runner.cancel()
            running.pump.cancel()
        }
        let runners = sessions.values.map(\.runner)
        sessions.removeAll()
        isListening = false
        if userInitiated { wantsListening = false }
        UIApplication.shared.isIdleTimerDisabled = false
        for id in statuses.keys { statuses[id] = .stopped }
        persist()
        return runners
    }

    /// Restarts the sessions so new settings take effect. Invalid settings
    /// leave the running sessions alone. The old registrations are removed
    /// before new ones are made, so the printer never lists the device twice.
    private func restartListening() async {
        guard isListening else { return }
        do {
            try preferences.validate()
        } catch {
            Self.log.debug("app: restart skipped, invalid settings: \(error)")
            lastError = "\(error). Still using the previous settings."
            return
        }
        Self.log.debug("app: restarting sessions for new settings")
        for runner in stopListening(userInitiated: false) {
            await runner.value
        }
        guard !Task.isCancelled, wantsListening, !isListening else {
            Self.log.debug("app: restart abandoned (stopped meanwhile)")
            return
        }
        startListening()
    }

    private func start(printer: PrinterRecord, folder: URL) {
        guard sessions[printer.id] == nil else { return }
        Self.log.debug("app: start session \(printer.displayName) \(printer.address)")
        let sink = FolderScanSink(directory: folder, securityScoped: false)
        let rediscover: PrinterSession.Rediscover = { record in
            await PrinterProbe.locate(record)
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
            if s.isReady { presence[id] = true }
            if s == .unreachable { presence[id] = false }
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
            stopPresenceChecks()
            guard isListening else { return }
            restartTask?.cancel()
            let running = Array(sessions.values)
            backgroundGuard.begin { [weak self] in
                self?.stopListening(userInitiated: false)
            }
            Task {
                // Let scans in flight land in the file, then unregister from
                // the printers before iOS suspends the app.
                await withTaskGroup(of: Void.self) { group in
                    for r in running {
                        group.addTask { await r.session.closeOpenDocument() }
                    }
                }
                for runner in stopListening(userInitiated: false) {
                    await runner.value
                }
                backgroundGuard.end()
            }
        case .active:
            startPresenceChecks()
            if wantsListening, !isListening, !printers.isEmpty { startListening() }
        default:
            break
        }
    }

    // MARK: - Printers

    /// Adds a printer unless it is already in the list (same UUID, Bonjour
    /// name or address); returns the existing entry in that case.
    @discardableResult
    func addPrinter(_ record: PrinterRecord, present: Bool = false) -> PrinterRecord? {
        if let existing = printers.first(where: { $0.isSamePrinter(as: record) }) {
            Self.log.debug("app: add printer skipped, same as \(existing.displayName)")
            return existing
        }
        Self.log.debug("app: add printer \(record.displayName) \(record.address) uuid=\(record.uuid ?? "-")")
        printers.append(record)
        if present { presence[record.id] = true }
        persist()
        if isListening, let folder = outputFolder, present || !record.isBonjour {
            start(printer: record, folder: folder.url)
        }
        return nil
    }

    /// Renames a printer; a running session restarts so logs and saved scans
    /// carry the new name.
    func renamePrinter(_ id: UUID, to name: String) {
        let name = name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty, let i = printers.firstIndex(where: { $0.id == id }),
              printers[i].displayName != name else { return }
        Self.log.debug("app: rename printer \(self.printers[i].displayName) -> \(name)")
        printers[i].displayName = name
        persist()
        guard let running = sessions.removeValue(forKey: id) else { return }
        running.runner.cancel()
        running.pump.cancel()
        let printer = printers[i]
        Task {
            await running.runner.value
            if isListening, let folder = outputFolder { start(printer: printer, folder: folder.url) }
        }
    }

    // MARK: - Recent scans

    /// Hides one scan from the list; its file is left where it was saved.
    func removeRecentScan(_ id: UUID) {
        Self.log.debug("app: remove recent scan \(id)")
        recentScans.removeAll { $0.id == id }
        persist()
    }

    /// Empties the list; the files are left where they were saved.
    func clearRecentScans() {
        Self.log.debug("app: clear recent scans count=\(self.recentScans.count)")
        recentScans.removeAll()
        persist()
    }

    // MARK: - Presence

    private func startPresenceChecks() {
        presenceTask?.cancel()
        presenceTask = Task {
            while !Task.isCancelled {
                await refreshPresence()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    private func stopPresenceChecks() {
        presenceTask?.cancel()
        presenceTask = nil
    }

    /// Checks the printers that have no running session; starts a session
    /// for each one that turned up while listening.
    func refreshPresence() async {
        let targets = printers.filter { sessions[$0.id] == nil }
        guard !targets.isEmpty else { return }
        Self.log.debug("app: presence check printers=\(targets.count)")
        await withTaskGroup(of: (UUID, String, Int, Bool).self) { group in
            for p in targets {
                group.addTask {
                    let found = await PrinterProbe.locate(p)
                    return (p.id, found?.host ?? "", found?.port ?? 0, found != nil)
                }
            }
            for await (id, host, port, present) in group {
                applyPresence(id, present ? (host, port) : nil)
            }
        }
    }

    private func applyPresence(_ id: UUID, _ found: (host: String, port: Int)?) {
        guard let i = printers.firstIndex(where: { $0.id == id }) else { return }
        presence[id] = found != nil
        Self.log.debug("app: \(self.printers[i].displayName) present=\(found != nil)")
        guard let found else { return }
        if printers[i].host != found.host || printers[i].port != found.port {
            printers[i].host = found.host
            printers[i].port = found.port
            persist()
        }
        if isListening, let folder = outputFolder { start(printer: printers[i], folder: folder.url) }
    }

    func removePrinter(_ record: PrinterRecord) {
        Self.log.debug("app: remove printer \(record.displayName)")
        printers.removeAll { $0.id == record.id }
        if let running = sessions.removeValue(forKey: record.id) {
            running.runner.cancel()
            running.pump.cancel()
        }
        statuses[record.id] = nil
        presence[record.id] = nil
        persist()
    }

    // MARK: - Settings

    /// Called after any edit to `preferences`. Sessions restart once the
    /// edits pause, not on every keystroke of the name field.
    func preferencesChanged() {
        persist()
        guard isListening else { return }
        restartTask?.cancel()
        restartTask = Task {
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await restartListening()
        }
    }

    func setOutputLocation(_ location: OutputLocation) {
        Self.log.debug("app: output location -> \(location.displayName)")
        outputLocation = location
        releaseOutputFolder()
        resolveOutputFolder()
        persist()
        if isListening {
            restartTask?.cancel()
            restartTask = Task { await restartListening() }
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
            folderProblem = nil
            return outputFolder
        } catch {
            Self.log.error("app: output folder unavailable: \(error)")
            if !outputLocation.isDocuments {
                folderProblem = "\(outputLocation.displayName) can't be opened right now (\(error.localizedDescription)). "
                    + "Scans are saved in the app folder until it is available again."
            }
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
