// Errors raised while talking to the printer.
import Foundation

/// An error from the LEDM layer. `status` carries the HTTP details so the
/// session can distinguish a vanished destination (404) from a dead printer.
public enum LEDMError: Error, Sendable, CustomStringConvertible {
    case status(method: String, path: String, status: Int, body: String)
    case missingLocation(String)
    case parse(String)
    case noPages(state: String)
    case timeout(String)
    case unsupportedPrinter(resources: [String])
    case invalidResponse(String)

    /// True when the printer answered 404.
    public var isNotFound: Bool {
        if case .status(_, _, 404, _) = self { return true }
        return false
    }

    public var description: String {
        switch self {
        case let .status(method, path, status, body):
            let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
            let short = trimmed.count > 300 ? String(trimmed.prefix(300)) + "..." : trimmed
            return "\(method) \(path): http \(status): \(short)"
        case let .missingLocation(what):
            return "\(what): printer replied without a Location header"
        case let .parse(what):
            return "parse: \(what)"
        case let .noPages(state):
            return "scan job ended in state \"\(state)\" without a page"
        case let .timeout(what):
            return "timeout: \(what)"
        case let .unsupportedPrinter(resources):
            return "printer offers neither WalkupScan nor WalkupScanToComp (resources: \(resources.joined(separator: ", ")))"
        case let .invalidResponse(what):
            return "invalid response: \(what)"
        }
    }
}
