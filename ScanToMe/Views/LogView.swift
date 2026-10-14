import ScanKit
import SwiftUI

struct LogView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        List(model.log.reversed()) { entry in
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(entry.date.formatted(date: .omitted, time: .standard))
                    Text(entry.printer)
                    Spacer()
                    Text(entry.level.rawValue.uppercased())
                        .foregroundStyle(color(for: entry.level))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                Text(entry.message).font(.footnote)
            }
        }
        .navigationTitle("Activity")
        .toolbar {
            Button {
                UIPasteboard.general.string = model.log.map {
                    "\($0.date.formatted(date: .numeric, time: .standard)) [\($0.level.rawValue)] \($0.printer): \($0.message)"
                }.joined(separator: "\n")
            } label: { Label("Copy", systemImage: "doc.on.doc") }
        }
    }

    private func color(for level: LogEntry.Level) -> Color {
        switch level {
        case .debug: return .secondary
        case .info: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
