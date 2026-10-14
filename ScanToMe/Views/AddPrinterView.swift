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
                        Button { add(scanner) } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(scanner.serviceName)
                                    Text(scanner.isHP ? (scanner.model ?? scanner.serviceName) : "may not be supported yet")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if resolving == scanner.serviceName { ProgressView() }
                            }
                        }
                        .disabled(resolving != nil)
                    }
                } header: {
                    Text("Found on the network")
                } footer: {
                    Text("If nothing shows up, allow Local Network access for Scan to Me in Settings > Privacy & Security.")
                }
                Section("Manual") {
                    TextField("Host (HPxxxxxx.local or IP)", text: $manualHost)
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
                Self.log.debug("add-printer: \(scanner.serviceName) -> \(r.host):\(r.port)")
                model.addPrinter(PrinterRecord(displayName: scanner.model ?? scanner.serviceName,
                                               serviceName: scanner.serviceName, host: r.host, port: r.port))
                dismiss()
            } catch {
                Self.log.error("add-printer: resolve failed: \(error)")
                self.error = "Could not resolve \(scanner.serviceName): \(error)"
            }
        }
    }

    private func addManual() {
        let host = manualHost.trimmingCharacters(in: .whitespaces)
        guard let port = Int(manualPort) else { return }
        model.addPrinter(PrinterRecord(displayName: host, host: host, port: port))
        dismiss()
    }
}
