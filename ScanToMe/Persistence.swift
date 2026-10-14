// One JSON file in Application Support holds everything the app remembers.
import Foundation
import ScanKit
import os

struct PersistedState: Codable, Sendable {
    var printers: [PrinterRecord]
    var preferences: ScanPreferences
    var outputLocation: OutputLocation
    var recentScans: [SavedScan]
    var wantsListening: Bool
}

enum Persistence {
    private static let log = Logger(subsystem: "com.obarlier.scantome", category: "persistence")

    static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return base.appendingPathComponent("ScanToMe", isDirectory: true).appendingPathComponent("state.json")
    }

    static func load() -> PersistedState? {
        let url = fileURL
        guard let data = try? Data(contentsOf: url) else {
            log.debug("persistence: no state file at \(url.path)")
            return nil
        }
        do {
            let state = try JSONDecoder().decode(PersistedState.self, from: data)
            log.debug("persistence: loaded \(data.count) bytes, printers=\(state.printers.count)")
            return state
        } catch {
            log.error("persistence: decode failed, starting fresh: \(error)")
            return nil
        }
    }

    static func save(_ state: PersistedState) {
        let url = fileURL
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: url, options: .atomic)
            log.debug("persistence: saved \(data.count) bytes")
        } catch {
            log.error("persistence: save failed: \(error)")
        }
    }
}
