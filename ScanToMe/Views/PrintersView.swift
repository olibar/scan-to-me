import ScanKit
import SwiftUI

struct PrintersView: View {
    @Environment(AppModel.self) private var model
    @State private var adding = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.printers) { printer in
                    VStack(alignment: .leading) {
                        Text(printer.displayName)
                        Text(printer.serviceName ?? printer.address).font(.caption).foregroundStyle(.secondary)
                        if printer.serviceName != nil {
                            Text(printer.address).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
                .onDelete { offsets in
                    for i in offsets { model.removePrinter(model.printers[i]) }
                }
                if model.printers.isEmpty {
                    Text("No printers yet. Tap + to find one on your network.").foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Printers")
            .toolbar {
                Button { adding = true } label: { Label("Add", systemImage: "plus") }
            }
            .sheet(isPresented: $adding) { AddPrinterView() }
        }
    }
}
