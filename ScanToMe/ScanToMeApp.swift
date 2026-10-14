// App entry point. The listener only runs while the app is in the
// foreground; scene phase changes start and stop it.
import SwiftUI

@main
struct ScanToMeApp: App {
    @State private var model = AppModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
        .onChange(of: scenePhase) { _, phase in
            model.scenePhaseChanged(phase)
        }
    }
}
