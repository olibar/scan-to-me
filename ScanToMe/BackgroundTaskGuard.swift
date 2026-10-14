// Buys the ~30 seconds iOS grants after backgrounding so an in-flight scan
// can finish and the open PDF can be written.
import os
import UIKit

@MainActor
final class BackgroundTaskGuard {
    private static let log = Logger(subsystem: "com.obarlier.scantome", category: "background")
    private var identifier: UIBackgroundTaskIdentifier = .invalid

    /// Starts a background task; `onExpire` runs if iOS runs out of patience.
    func begin(onExpire: @escaping @MainActor () -> Void) {
        end()
        identifier = UIApplication.shared.beginBackgroundTask(withName: "scantome.finish-scan") { [weak self] in
            Self.log.warning("background: task expired")
            onExpire()
            self?.end()
        }
        Self.log.debug("background: task begun id=\(self.identifier.rawValue)")
    }

    func end() {
        guard identifier != .invalid else { return }
        Self.log.debug("background: task ended id=\(self.identifier.rawValue)")
        UIApplication.shared.endBackgroundTask(identifier)
        identifier = .invalid
    }
}
