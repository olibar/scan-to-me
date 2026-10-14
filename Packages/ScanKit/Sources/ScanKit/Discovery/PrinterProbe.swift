// Is a printer on the current network right now? Printers found through
// Bonjour are looked up by identity, so an identical printer elsewhere that
// happens to use the same address is never mistaken for them; printers added
// by address are asked directly.
import Foundation

public enum PrinterProbe {
    /// Where the printer answers now, nil when it is not on this network.
    public static func locate(_ printer: PrinterRecord, timeout: Duration = .seconds(5),
                              transport: (any HTTPTransport)? = nil) async -> (host: String, port: Int)? {
        Log.discover.debug("discover: probing \(printer.displayName) bonjour=\(printer.isBonjour)")
        if printer.isBonjour {
            guard let found = await ScannerBrowser.find(printer, timeout: timeout) else {
                Log.discover.debug("discover: \(printer.displayName) not announced on this network")
                return nil
            }
            do {
                let r = try await EndpointResolver.resolve(found.endpoint)
                Log.discover.debug("discover: \(printer.displayName) present at \(r.host):\(r.port)")
                return (r.host, r.port)
            } catch {
                Log.discover.debug("discover: \(printer.displayName) announced but not resolvable: \(error)")
                return nil
            }
        }
        let present = await answers(host: printer.host, port: printer.port, transport: transport)
        Log.discover.debug("discover: \(printer.displayName) at \(printer.address) answers=\(present)")
        return present ? (printer.host, printer.port) : nil
    }

    /// True when the address answers on LEDM or eSCL.
    static func answers(host: String, port: Int, transport: (any HTTPTransport)?) async -> Bool {
        let ledm = LEDMClient(host: host, port: port, transport: transport)
        if let r = try? await ledm.request("GET", "/DevMgmt/DiscoveryTree.xml", timeout: 5), (200...299).contains(r.status) {
            return true
        }
        return await ESCLClient.locate(host: host, recordedPort: port, transport: transport) != nil
    }
}
