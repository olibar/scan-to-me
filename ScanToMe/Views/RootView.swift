import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            ListeningView()
                .tabItem { Label("Listen", systemImage: "dot.radiowaves.left.and.right") }
            PrintersView()
                .tabItem { Label("Printers", systemImage: "printer") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
