// The single seam between the LEDM client and the network, so tests can
// script a fake printer without opening sockets.
import Foundation

/// Sends one HTTP request and returns the body and response.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

extension URLSession: HTTPTransport {
    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw LEDMError.invalidResponse("non-HTTP response for \(request.url?.absoluteString ?? "?")")
        }
        return (data, http)
    }
}
