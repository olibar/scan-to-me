// Turns a Bonjour service endpoint into host:port. NWBrowser never exposes
// the SRV record, so we open a TCP connection to the service and read the
// remote address of the path once it is ready.
import Foundation
import Network

public enum EndpointResolver {
    public struct Resolved: Sendable, Equatable {
        public let host: String
        public let port: Int
    }

    public static func resolve(_ endpoint: NWEndpoint, timeout: Duration = .seconds(5)) async throws -> Resolved {
        if case let .hostPort(host, port) = endpoint {
            return Resolved(host: render(host), port: Int(port.rawValue))
        }
        Log.discover.debug("discover: resolving \(String(describing: endpoint))")
        let params = NWParameters.tcp
        // Prefer IPv4: HP printers announce over IPv4 and link-local IPv6
        // addresses need a scope suffix that URLSession handles poorly.
        if let ip = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
            ip.version = .v4
        }
        let connection = NWConnection(to: endpoint, using: params)
        let states = AsyncStream<NWConnection.State> { continuation in
            connection.stateUpdateHandler = { state in
                continuation.yield(state)
                if case .cancelled = state { continuation.finish() }
            }
            continuation.onTermination = { _ in connection.cancel() }
        }
        connection.start(queue: DispatchQueue(label: "com.obarlier.scantome.resolver"))
        return try await withThrowingTaskGroup(of: Resolved.self) { group in
            group.addTask {
                for await state in states {
                    switch state {
                    case .ready:
                        guard case let .hostPort(host, port)? = connection.currentPath?.remoteEndpoint else {
                            throw LEDMError.invalidResponse("resolver: ready without remote endpoint")
                        }
                        let r = Resolved(host: render(host), port: Int(port.rawValue))
                        Log.discover.debug("discover: resolved \(r.host):\(r.port)")
                        return r
                    case let .failed(error):
                        throw LEDMError.timeout("resolver: \(error)")
                    case let .waiting(error):
                        Log.discover.debug("discover: resolver waiting: \(error)")
                    default:
                        break
                    }
                }
                throw LEDMError.timeout("resolver: connection cancelled")
            }
            group.addTask {
                try await Task.sleep(for: timeout)
                throw LEDMError.timeout("resolving \(String(describing: endpoint)) took more than \(timeout)")
            }
            defer {
                group.cancelAll()
                connection.cancel()
            }
            guard let first = try await group.next() else {
                throw LEDMError.timeout("resolver: no result")
            }
            return first
        }
    }

    /// Renders a host without the interface scope ("%en0") that Network
    /// appends to link-scoped addresses; URLs do not accept it.
    static func render(_ host: NWEndpoint.Host) -> String {
        switch host {
        case let .ipv4(addr): return stripScope("\(addr)")
        case let .ipv6(addr): return stripScope("\(addr)")
        case let .name(name, _): return stripScope(name)
        @unknown default: return stripScope("\(host)")
        }
    }

    static func stripScope(_ s: String) -> String {
        guard let pct = s.firstIndex(of: "%") else { return s }
        return String(s[..<pct])
    }
}
