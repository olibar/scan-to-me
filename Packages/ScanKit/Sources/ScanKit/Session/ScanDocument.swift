// A multi-page PDF being assembled.
import Foundation

struct ScanDocument: Sendable {
    var pages: [PDFWriter.Page] = []
    let started: Date
    var lastPage: Date

    init(now: Date = Date()) {
        started = now
        lastPage = now
    }

    func isExpired(now: Date, timeout: TimeInterval) -> Bool {
        now.timeIntervalSince(lastPage) > timeout
    }
}
