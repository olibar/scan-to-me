// Bonjour browsing for _scanner._tcp with Network.framework.
import Foundation
import Network

public enum ScannerBrowser {
    public static let serviceType = "_scanner._tcp"

    /// Streams the current set of scanners every time it changes. The
    /// browser is cancelled when the consumer stops iterating.
    public static func browse() -> AsyncStream<[DiscoveredScanner]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let params = NWParameters()
            params.includePeerToPeer = false
            let browser = NWBrowser(for: .bonjourWithTXTRecord(type: serviceType, domain: nil), using: params)
            Log.discover.debug("discover: browsing \(serviceType)")
            browser.stateUpdateHandler = { state in
                switch state {
                case let .failed(error):
                    Log.discover.error("discover: browser failed: \(error)")
                    continuation.finish()
                case .cancelled:
                    continuation.finish()
                default:
                    Log.discover.debug("discover: browser state \(String(describing: state))")
                }
            }
            browser.browseResultsChangedHandler = { results, _ in
                let scanners = results.compactMap(scanner(from:))
                Log.discover.debug("discover: results=\(scanners.count)")
                continuation.yield(scanners)
            }
            continuation.onTermination = { _ in
                Log.discover.debug("discover: browse finished")
                browser.cancel()
            }
            browser.start(queue: DispatchQueue(label: "com.obarlier.scantome.browser"))
        }
    }

    /// Waits until a scanner with this instance name shows up, or the timeout passes.
    public static func find(serviceName: String, timeout: Duration = .seconds(5)) async -> DiscoveredScanner? {
        Log.discover.debug("discover: looking for \(serviceName)")
        let want = serviceName.lowercased()
        return await withTaskGroup(of: DiscoveredScanner?.self) { group in
            group.addTask {
                for await list in browse() {
                    if let hit = list.first(where: { $0.serviceName.lowercased() == want }) { return hit }
                }
                return nil
            }
            group.addTask {
                try? await Task.sleep(for: timeout)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    static func scanner(from result: NWBrowser.Result) -> DiscoveredScanner? {
        guard case let .service(name, _, _, _) = result.endpoint else { return nil }
        var model: String?
        var mfg: String?
        if case let .bonjour(txt) = result.metadata {
            model = txt.dictionary["ty"]
            mfg = txt.dictionary["mfg"]
        }
        return DiscoveredScanner(serviceName: name, model: model, mfg: mfg, endpoint: result.endpoint)
    }
}
