import ScanKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @State private var pickingFolder = false

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section("On the printer") {
                    TextField("Name shown on the printer", text: $model.preferences.destinationName)
                }
                Section("Scan") {
                    Picker("Format", selection: $model.preferences.format) {
                        Text("PDF").tag(OutputFormat.pdf)
                        Text("JPEG").tag(OutputFormat.jpeg)
                    }
                    Picker("Resolution", selection: $model.preferences.resolution) {
                        ForEach(ScanPreferences.resolutionChoices, id: \.self) { Text("\($0) dpi").tag($0) }
                    }
                    Picker("Color", selection: $model.preferences.colorMode) {
                        Text("Color").tag(ColorMode.color)
                        Text("Grayscale").tag(ColorMode.gray)
                    }
                    Picker("Paper", selection: $model.preferences.paper) {
                        Text("A4").tag(Paper.a4)
                        Text("Letter").tag(Paper.letter)
                    }
                    Stepper(value: $model.preferences.pageTimeout, in: 30...600, step: 30) {
                        Text("Close PDF after \(Int(model.preferences.pageTimeout)) s idle")
                    }
                }
                Section {
                    TextField("Pattern", text: $model.preferences.filenamePattern)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Preview: \(FilenamePattern.render(model.preferences.filenamePattern, date: Date(), page: 1)).\(model.preferences.format.fileExtension)")
                        .font(.caption).foregroundStyle(.secondary)
                } header: {
                    Text("File name")
                } footer: {
                    Text("Tokens: {date} {time} {page}. A shortcut chosen on the printer (Save as Document / Save as Photo) overrides the format.")
                }
                Section {
                    LabeledContent("Folder", value: model.outputLocation.displayName)
                    if let problem = model.folderProblem {
                        Text(problem).font(.footnote).foregroundStyle(.red)
                    }
                    Button("Choose folder...") { pickingFolder = true }
                    if !model.outputLocation.isDocuments {
                        Button("Use the app folder") { model.setOutputLocation(.documents) }
                    }
                    Toggle("Also add JPEG scans to Photos", isOn: $model.preferences.saveJPEGToPhotos)
                } header: {
                    Text("Save to")
                } footer: {
                    Text("The app folder is visible in Files under On My iPhone > Scan to Me. For iCloud Drive, Dropbox, Google Drive or OneDrive, tap Choose folder, then Browse. A service missing there must be switched on in the Files app: Browse > ... > Edit.")
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-")
                    Text("Scan to Me appears on the printer only while the app is open and listening. iOS suspends network access in the background.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .onChange(of: model.preferences) { _, _ in model.preferencesChanged() }
            .sheet(isPresented: $pickingFolder) {
                OutputFolderPicker { location in model.setOutputLocation(location) }
                    .ignoresSafeArea()
            }
        }
    }
}
