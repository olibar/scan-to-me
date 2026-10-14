// Where scans are saved: the app's Documents folder (visible in Files) or a
// folder the user picked, kept as a security-scoped bookmark.
import Foundation

enum OutputLocation: Codable, Equatable, Sendable {
    case documents
    case bookmark(Data, displayName: String)

    enum LocationError: Error, LocalizedError {
        case accessDenied
        case noDocuments

        var errorDescription: String? {
            switch self {
            case .accessDenied: return "access to the chosen folder was denied"
            case .noDocuments: return "the app's Documents folder could not be found"
            }
        }
    }

    var displayName: String {
        switch self {
        case .documents: return "On My iPhone / Scan to Me"
        case let .bookmark(_, name): return name
        }
    }

    var isDocuments: Bool {
        if case .documents = self { return true }
        return false
    }

    /// Resolves to a folder URL. `scoped` tells the caller to bracket access
    /// with start/stopAccessingSecurityScopedResource.
    func resolve() throws -> (url: URL, scoped: Bool, stale: Bool) {
        switch self {
        case .documents:
            guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                throw LocationError.noDocuments
            }
            return (docs, false, false)
        case let .bookmark(data, _):
            var stale = false
            let url = try URL(resolvingBookmarkData: data, options: [], relativeTo: nil, bookmarkDataIsStale: &stale)
            return (url, true, stale)
        }
    }
}
