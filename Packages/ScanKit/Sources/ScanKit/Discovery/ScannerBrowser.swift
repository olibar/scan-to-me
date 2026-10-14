// Bonjour browsing for scanners with Network.framework: _scanner._tcp (LEDM
// printers) and _uscan._tcp (eSCL printers, some of which announce only that).
import Foundation
import Network

public enum ScannerBrowser {
    /// In order of preference when a printer announces both.
    public static let serviceTypes = ["_scanner._tcp", "_uscan._tcp"]

    /// Latest results per service type. Only touched on the browsers' queue.
    private final class Results: @unchecked Sendable {
        var byType: [String: [DiscoveredScanner]] = [:]

        /// One entry per instance name, the preferred service type winning.
        var merged: [DiscoveredScanner] {
            var seen = Set<String>()
            var out: [DiscoveredScanner] = []
            for type in serviceTypes {
                for s in byType[type] ?? [] where seen.insert(s.serviceName.lowercased()).inserted {
                    out.append(s)
                }
            }
            return out
        }
    }

    /// Streams the current set of scanners every time it changes. The
    /// browsers are cancelled when the consumer stops iterating.
    public static func browse() -> AsyncStream<[DiscoveredScanner]> {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let queue = DispatchQueue(label: "com.obarlier.scantome.browser")
            let results = Results()
            var browsers: [NWBrowser] = []
            for type in serviceTypes {
                let params = NWParameters()
                params.includePeerToPeer = false
                let browser = NWBrowser(for: .bonjourWithTXTRecord(type: type, domain: nil), using: params)
                Log.discover.debug("discover: browsing \(type)")
                browser.stateUpdateHandler = { state in
                    switch state {
                    case let .failed(error):
                        // One type failing must not end the other's results.
                        Log.discover.error("discover: browser \(type) failed: \(error)")
                    default:
                        Log.discover.debug("discover: browser \(type) state \(String(describing: state))")
                    }
                }
                browser.browseResultsChangedHandler = { found, _ in
                    results.byType[type] = found.compactMap(scanner(from:))
                    let merged = results.merged
                    Log.discover.debug("discover: \(type) results=\(found.count) merged=\(merged.count)")
                    continuation.yield(merged)
                }
                browser.start(queue: queue)
                browsers.append(browser)
            }
            let all = browsers
            continuation.onTermination = { _ in
                Log.discover.debug("discover: browse finished")
                for b in all { b.cancel() }
            }
        }
    }

    /// Waits until this printer is announced (matched by UUID or Bonjour
    /// name), or the timeout passes.
    public static func find(_ printer: PrinterRecord, timeout: Duration = .seconds(5)) async -> DiscoveredScanner? {
        Log.discover.debug("discover: looking for \(printer.serviceName ?? printer.address) uuid=\(printer.uuid ?? "-")")
        return await withTaskGroup(of: DiscoveredScanner?.self) { group in
            group.addTask {
                for await list in browse() {
                    if let hit = list.first(where: { printer.matches($0) }) { return hit }
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
        var uuid: String?
        if case let .bonjour(txt) = result.metadata {
            model = txt.dictionary["ty"]
            mfg = txt.dictionary["mfg"]
            uuid = txt.dictionary["UUID"]
        }
        return DiscoveredScanner(serviceName: name, model: model, mfg: mfg, uuid: uuid, endpoint: result.endpoint)
    }
}
