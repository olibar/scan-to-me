// Finds _scanner._tcp services on the network, or takes a manual address.
import ScanKit
import os
import SwiftUI

struct AddPrinterView: View {
    private static let log = Logger(subsystem: "com.obarlier.scantome", category: "add-printer")

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var found: [DiscoveredScanner] = []
    @State private var resolving: String?
    @State private var error: String?
    @State private var manualHost = ""
    @State private var manualPort = "8080"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if found.isEmpty {
                        HStack {
                            ProgressView()
                            Text("Looking for scanners...").foregroundStyle(.secondary)
                        }
                    }
                    ForEach(found.sorted { $0.isHP && !$1.isHP }) { scanner in
                        let existing = model.printers.first { $0.matches(scanner) }
                        Button { add(scanner) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(scanner.serviceName)
                                    Group {
                                        if scanner.isHP {
                                            Text(verbatim: scanner.model ?? "")
                                        } else {
                                            Text("may not be supported yet")
                                        }
                                    }
                                    .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if resolving == scanner.serviceName { ProgressView() }
                                if let existing {
                                    Text("Added as \(existing.displayName)").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(resolving != nil || existing != nil)
                    }
                } header: {
                    Text("Found on the network")
                } footer: {
                    Text("If nothing shows up, allow Local Network access for Scan to Me in Settings > Privacy & Security.")
                }
                Section("Manual") {
                    TextField("Host name (.local) or IP address", text: $manualHost)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("Port", text: $manualPort).keyboardType(.numberPad)
                    Button("Add printer") { addManual() }
                        .disabled(manualHost.trimmingCharacters(in: .whitespaces).isEmpty || Int(manualPort) == nil)
                }
                if let error {
                    Section { Text(error).foregroundStyle(.red) }
                }
            }
            .navigationTitle("Add printer")
            .toolbar {
                Button("Cancel") { dismiss() }
            }
            .task {
                for await list in ScannerBrowser.browse() {
                    found = list
                }
            }
        }
    }

    private func add(_ scanner: DiscoveredScanner) {
        resolving = scanner.serviceName
        error = nil
        Task {
            defer { resolving = nil }
            do {
                let r = try await EndpointResolver.resolve(scanner.endpoint)
                Self.log.debug("add-printer: \(scanner.serviceName) -> \(r.host):\(r.port) uuid=\(scanner.uuid ?? "-")")
                // The Bonjour name is unique per printer (it ends with part of
                // the MAC address), unlike the model.
                let record = PrinterRecord(displayName: scanner.serviceName, serviceName: scanner.serviceName,
                                           uuid: scanner.uuid, host: r.host, port: r.port)
                if let existing = model.addPrinter(record, present: true) {
                    self.error = String(localized: "This printer is already in your list as \"\(existing.displayName)\".")
                    return
                }
                dismiss()
            } catch {
                Self.log.error("add-printer: resolve failed: \(error)")
                self.error = String(localized: "Could not resolve \(scanner.serviceName): \(error.localizedDescription)")
            }
        }
    }

    private func addManual() {
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        guard let port = Int(manualPort) else { return }
        if let existing = model.addPrinter(PrinterRecord(displayName: host, host: host, port: port)) {
            error = String(localized: "\(host):\(port) is already in your list as \"\(existing.displayName)\".")
            return
        }
        dismiss()
    }
}
