import SwiftUI

struct RootView: View {
    @State private var tab = RootView.initialTab

    var body: some View {
        TabView(selection: $tab) {
            ListeningView()
                .tabItem { Label("Listen", systemImage: "dot.radiowaves.left.and.right") }
                .tag("listen")
            PrintersView()
                .tabItem { Label("Printers", systemImage: "printer") }
                .tag("printers")
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag("settings")
        }
    }

    /// Debug builds only: `-ScreenshotTab printers|settings` opens that tab, so
    /// design/screenshots.sh can capture every screen in the simulator.
    private static var initialTab: String {
        #if DEBUG
        return UserDefaults.standard.string(forKey: "ScreenshotTab") ?? "listen"
        #else
        return "listen"
        #endif
    }
}
