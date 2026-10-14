// Folder picker wrapped for SwiftUI. Returns a bookmark so the folder stays
// reachable across launches.
import os
import SwiftUI
import UIKit
import UniformTypeIdentifiers

struct OutputFolderPicker: UIViewControllerRepresentable {
    let onPick: (OutputLocation) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private static let log = Logger(subsystem: "com.obarlier.scantome", category: "picker")
        let onPick: (OutputLocation) -> Void

        init(onPick: @escaping (OutputLocation) -> Void) { self.onPick = onPick }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            guard let url = urls.first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                // iOS bookmarks carry the security scope without an explicit option.
                let data = try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                Self.log.debug("picker: folder picked \(url.path) bookmarkBytes=\(data.count)")
                onPick(.bookmark(data, displayName: url.lastPathComponent))
            } catch {
                Self.log.error("picker: bookmark failed for \(url.path): \(error)")
            }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            Self.log.debug("picker: cancelled")
        }
    }
}
