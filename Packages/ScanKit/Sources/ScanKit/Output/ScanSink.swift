// Where finished scans go.
import Foundation

/// Receives a finished file. Implementations pick a unique name from
/// `baseName` and `ext` and return the final location.
public protocol ScanSink: Sendable {
    func write(_ data: Data, baseName: String, ext: String) async throws -> URL
}
