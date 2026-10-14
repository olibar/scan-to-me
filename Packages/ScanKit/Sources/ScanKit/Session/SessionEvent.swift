// What a printer session reports to the UI.
import Foundation

public enum SessionStatus: Sendable, Equatable {
    case connecting
    case ready(flavor: WalkupFlavor, hasAdf: Bool)
    case scanning(pagesSoFar: Int)
    case waitingForMorePages(pages: Int)
    case error(String)
    case stopped

    public var isReady: Bool {
        if case .ready = self { return true }
        return false
    }
}

public struct LogEntry: Sendable, Identifiable, Equatable {
    public enum Level: String, Sendable { case debug, info, warning, error }

    public let id: UUID
    public let date: Date
    public let level: Level
    public let printer: String
    public let message: String

    public init(id: UUID = UUID(), date: Date = Date(), level: Level, printer: String, message: String) {
        self.id = id
        self.date = date
        self.level = level
        self.printer = printer
        self.message = message
    }
}

public struct SavedScan: Sendable, Identifiable, Equatable, Codable {
    public let id: UUID
    public let url: URL
    public let date: Date
    public let pages: Int
    public let format: OutputFormat
    public let printer: String

    public init(id: UUID = UUID(), url: URL, date: Date = Date(), pages: Int, format: OutputFormat, printer: String) {
        self.id = id
        self.url = url
        self.date = date
        self.pages = pages
        self.format = format
        self.printer = printer
    }
}

public enum SessionEvent: Sendable {
    case status(SessionStatus)
    case log(LogEntry)
    case saved(SavedScan)
    /// The printer answered at a new address (found again via Bonjour).
    case addressChanged(host: String, port: Int)
}
