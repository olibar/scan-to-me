// The main screen: start/stop, per-printer state, recent scans.
import ScanKit
import QuickLook
import SwiftUI

struct ListeningView: View {
    @Environment(AppModel.self) private var model
    @State private var previewURL: URL?

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
                    StatusBadge(status: model.statuses[printer.id] ?? .stopped)
                }
            }
        }
    }

    private var recentSection: some View {
        Section("Recent scans") {
            if model.recentScans.isEmpty {
                Text("No scans yet.").foregroundStyle(.secondary)
            }
            ForEach(model.recentScans) { scan in
                let exists = FileManager.default.fileExists(atPath: scan.url.path)
                HStack {
                    Image(systemName: scan.format == .pdf ? "doc.richtext" : "photo")
                    VStack(alignment: .leading) {
                        Text(scan.url.lastPathComponent).lineLimit(1)
                        Text("\(scan.date.formatted(date: .abbreviated, time: .shortened)) - \(scan.pages) page\(scan.pages == 1 ? "" : "s") - \(scan.printer)")
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
            }
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
            Label("\(pages) page\(pages == 1 ? "" : "s"), more?", systemImage: "doc.on.doc").foregroundStyle(.blue)
        case let .error(message):
            Label("Error", systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                .help(message)
        case .stopped:
            Label("Stopped", systemImage: "pause.circle").foregroundStyle(.secondary)
        }
    }
}
