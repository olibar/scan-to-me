// The main screen: start/stop, per-printer state, recent scans.
import ScanKit
import QuickLook
import SwiftUI

struct ListeningView: View {
    @Environment(AppModel.self) private var model
    @State private var previewURL: URL?
    @State private var confirmingClear = false
    @State private var pendingDelete: SavedScan?

    var body: some View {
        NavigationStack {
            List {
                controlSection
                if !model.printers.isEmpty { printersSection }
                recentSection
            }
            .navigationTitle("Scan to Me")
            .toolbar {
                NavigationLink { LogView() } label: { Label("Log", systemImage: "doc.text.magnifyingglass") }
            }
            .quickLookPreview($previewURL)
        }
    }

    private var controlSection: some View {
        Section {
            if model.printers.isEmpty {
                Text("Add a printer in the Printers tab to get started.")
                    .foregroundStyle(.secondary)
            } else {
                Button {
                    if model.isListening { model.stopListening() } else { model.startListening() }
                } label: {
                    Label(model.isListening ? "Stop listening" : "Start listening",
                          systemImage: model.isListening ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title3)
                }
            }
            if let error = model.lastError {
                Text(error).font(.footnote).foregroundStyle(.red)
            }
            if let problem = model.folderProblem {
                Text(problem).font(.footnote).foregroundStyle(.orange)
            }
        } footer: {
            Text(model.isListening
                 ? "The screen stays on while listening. Leave Scan to Me open, then on the printer choose Scan > Computer > \"\(model.preferences.destinationName)\"."
                 : "Scan to Me only appears on the printer while this app is open and listening.")
        }
    }

    private var printersSection: some View {
        Section("Printers") {
            ForEach(model.printers) { printer in
                HStack {
                    VStack(alignment: .leading) {
                        Text(printer.displayName)
                        Text(printer.address).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    PrinterStatusView(printer: printer)
                }
            }
        }
    }

    private var recentSection: some View {
        Section {
            if model.recentScans.isEmpty {
                Text("No scans yet.").foregroundStyle(.secondary)
            }
            ForEach(model.recentScans) { scan in
                let exists = FileManager.default.fileExists(atPath: scan.url.path)
                HStack {
                    Image(systemName: scan.format == .pdf ? "doc.richtext" : "photo")
                    VStack(alignment: .leading) {
                        Text(scan.url.lastPathComponent).lineLimit(1)
                        Text("\(scan.date.formatted(date: .abbreviated, time: .shortened)) - \(scan.pages) pages - \(scan.printer)")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if exists {
                        ShareLink(item: scan.url) { Image(systemName: "square.and.arrow.up") }
                            .buttonStyle(.borderless)
                    } else {
                        Text("moved").font(.caption).foregroundStyle(.tertiary)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { if exists { previewURL = scan.url } }
                // A full swipe reaches Delete (outermost), which always asks first;
                // a partial swipe also offers Remove, which keeps the file.
                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                    if exists {
                        Button { pendingDelete = scan } label: { Label("Delete", systemImage: "trash") }
                            .tint(.red)
                    }
                    Button { model.removeRecentScan(scan.id) } label: { Label("Remove", systemImage: "eye.slash") }
                        .tint(.gray)
                }
            }
        } header: {
            HStack {
                Text("Recent scans")
                Spacer()
                if !model.recentScans.isEmpty {
                    Button("Clear") { confirmingClear = true }
                        .font(.footnote)
                        .textCase(nil)
                }
            }
        } footer: {
            if !model.recentScans.isEmpty {
                Text("Swipe left on a scan: Remove hides it here and keeps the file; Delete also deletes the file.")
            }
        }
        .confirmationDialog("Clear the list of recent scans?", isPresented: $confirmingClear, titleVisibility: .visible) {
            Button("Clear list", role: .destructive) { model.clearRecentScans() }
        } message: {
            Text("The scanned files stay in their folder.")
        }
        .confirmationDialog("Delete this scan?", isPresented: Binding(get: { pendingDelete != nil },
                                                                      set: { if !$0 { pendingDelete = nil } }),
                            titleVisibility: .visible, presenting: pendingDelete) { scan in
            Button("Delete file", role: .destructive) {
                Task { await model.deleteScan(scan) }
            }
        } message: { scan in
            Text("\(scan.url.lastPathComponent) will be deleted from its folder. This cannot be undone.")
        }
    }
}

struct StatusBadge: View {
    let status: SessionStatus

    var body: some View {
        switch status {
        case .connecting:
            Label("Connecting", systemImage: "antenna.radiowaves.left.and.right").foregroundStyle(.orange)
        case let .ready(_, hasAdf):
            Label(hasAdf ? "Ready (feeder)" : "Ready", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case let .scanning(pages):
            Label(pages > 0 ? "Scanning (\(pages))" : "Scanning", systemImage: "scanner").foregroundStyle(.blue)
        case let .waitingForMorePages(pages):
            Label("\(pages) pages, more?", systemImage: "doc.on.doc").foregroundStyle(.blue)
        case let .error(message):
            Label("Error", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                .help(message)
        case .unreachable:
            Label("Not on this network", systemImage: "wifi.slash").foregroundStyle(.secondary)
        case .stopped:
            Label("Stopped", systemImage: "pause.circle").foregroundStyle(.secondary)
        }
    }
}

/// The session's status while listening, otherwise whether the printer is on
/// the current network.
struct PrinterStatusView: View {
    @Environment(AppModel.self) private var model
    let printer: PrinterRecord

    var body: some View {
        if model.isListening, let status = model.statuses[printer.id], status != .stopped {
            StatusBadge(status: status)
        } else {
            switch model.presence[printer.id] {
            case .none:
                Label("Checking", systemImage: "ellipsis.circle").foregroundStyle(.secondary)
            case .some(true):
                Label("Online", systemImage: "wifi").foregroundStyle(.green)
            case .some(false):
                Label("Not on this network", systemImage: "wifi.slash").foregroundStyle(.secondary)
            }
        }
    }
}
