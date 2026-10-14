// The printer list: status per printer, rename and remove via the detail
// screen, swipe or Edit.
import ScanKit
import SwiftUI

struct PrintersView: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.printers) { printer in
                    NavigationLink {
                        PrinterDetailView(printerID: printer.id)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(printer.displayName)
                            Text(printer.serviceName ?? printer.address).font(.caption).foregroundStyle(.secondary)
                            PrinterStatusView(printer: printer).font(.caption)
                        }
                    }
                }
                .onDelete { offsets in
                    for printer in offsets.map({ model.printers[$0] }) { model.removePrinter(printer) }
                }
                if model.printers.isEmpty {
                    Text("No printers yet. Tap + to find one on your network.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Printers")
            .refreshable { await model.refreshPresence() }
            .toolbar {
                if !model.printers.isEmpty { EditButton() }
                Button { adding = true } label: { Label("Add", systemImage: "plus") }
            }
            .sheet(isPresented: $adding) { AddPrinterView() }
        }
    }
}

/// Name, status, details and removal of one printer.
struct PrinterDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let printerID: UUID
    @State private var name = ""
    @State private var checking = false
    @State private var confirmingRemove = false

    private var printer: PrinterRecord? { model.printers.first { $0.id == printerID } }

    var body: some View {
        Form {
            if let printer {
                Section {
                    TextField("Name", text: $name)
                        .onSubmit { model.renamePrinter(printerID, to: name) }
                } header: {
                    Text("Name")
                } footer: {
                    Text("Shown in this app only, e.g. Home or Office. Setting the printer's Location in its web page names it automatically when added.")
                }
                Section("Status") {
                    PrinterStatusView(printer: printer)
                    Button(checking ? "Checking..." : "Check now") {
                        checking = true
                        Task {
                            await model.refreshPresence()
                            checking = false
                        }
                    }
                    .disabled(checking)
                }
                Section("Details") {
                    LabeledContent("Network name", value: printer.serviceName ?? "Added by address")
                    LabeledContent("Address", value: printer.address)
                }
                Section {
                    Button("Remove printer", role: .destructive) { confirmingRemove = true }
                }
            }
        }
        .navigationTitle(printer?.displayName ?? "Printer")
        .onAppear { name = printer?.displayName ?? "" }
        .onDisappear { model.renamePrinter(printerID, to: name) }
        .confirmationDialog("Remove this printer?", isPresented: $confirmingRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let printer { model.removePrinter(printer) }
                dismiss()
            }
        } message: {
            Text("Scan to Me stops listening for it. You can add it again later.")
        }
    }
}
