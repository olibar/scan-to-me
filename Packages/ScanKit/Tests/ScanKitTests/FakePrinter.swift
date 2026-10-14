// An in-memory WalkupScanToComp printer behind the HTTPTransport seam.
import Foundation
@testable import ScanKit

actor FakePrinter: HTTPTransport {
    var registrations = 0
    var scans = 0
    var jobPolls = 0
    var eventType = "HostSelected"
    var aging = 0
    var adfLoaded = false
    var destinationMissing = false
    var shortcut = "SavePDF"
    var expectedName = "Test Phone"
    var jpeg = Fixtures.jpeg(width: 30, height: 40, components: 3)
    var deletes = 0
    /// Some firmwares send no ETag, so the event table cannot long-poll.
    var sendsETag = true
    var requests: [String] = []

    let destURI = "/WalkupScanToComp/WalkupScanToCompDestinations/abc-123"

    func fire(_ type: String) {
        eventType = type
        aging += 1
    }

    func setAdfLoaded(_ v: Bool) { adfLoaded = v }
    func setShortcut(_ s: String) { shortcut = s }
    func setDestinationMissing(_ v: Bool) { destinationMissing = v }
    func setSendsETag(_ v: Bool) { sendsETag = v }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let url = request.url!
        let path = url.path
        let method = request.httpMethod ?? "GET"
        requests.append("\(method) \(path)")
        func reply(_ status: Int, _ body: Data = Data(), headers: [String: String] = [:]) -> (Data, HTTPURLResponse) {
            (body, HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!)
        }
        switch (method, path) {
        case ("GET", "/DevMgmt/DiscoveryTree.xml"):
            return reply(200, Fixtures.discoveryTree)
        case ("GET", "/Scan/ScanCaps"):
            return reply(200, Fixtures.scanCaps(adf: adfLoaded))
        case ("GET", "/Scan/Status"):
            return reply(200, Fixtures.status(adfLoaded: adfLoaded))
        case ("POST", "/WalkupScanToComp/WalkupScanToCompDestinations"):
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            guard body.contains("<dd:Name>\(expectedName)</dd:Name>") else { return reply(400, Data("bad body".utf8)) }
            registrations += 1
            destinationMissing = false
            return reply(201, headers: ["Location": destURI])
        case ("DELETE", destURI):
            deletes += 1
            return reply(200)
        case ("GET", destURI):
            if destinationMissing { return reply(404, Data("gone".utf8)) }
            return reply(200, Fixtures.destination(shortcut: shortcut))
        case ("GET", "/WalkupScanToComp/WalkupScanToCompEvent"):
            return reply(200, Fixtures.compEvent(eventType))
        case ("GET", "/EventMgmt/EventTable"):
            let etag = String(aging)
            if request.value(forHTTPHeaderField: "If-None-Match") == etag {
                try await Task.sleep(for: .milliseconds(30))
                return reply(304)
            }
            return reply(200, Fixtures.eventTable(aging: aging), headers: sendsETag ? ["ETag": etag] : [:])
        case ("POST", "/Scan/Jobs"):
            let body = String(decoding: request.httpBody ?? Data(), as: UTF8.self)
            let want = adfLoaded ? "<scan:InputSource>Adf</scan:InputSource>" : "<scan:InputSource>Platen</scan:InputSource>"
            guard body.contains(want) else { return reply(400, Data("bad scan job".utf8)) }
            scans += 1
            jobPolls = 0
            return reply(201, headers: ["Location": "/Scan/Jobs/\(scans)"])
        case ("GET", _) where path.hasPrefix("/Scan/Jobs/"):
            jobPolls += 1
            return reply(200, jobDocument())
        case ("GET", _) where path.hasPrefix("/Scan/Pages/"):
            return reply(200, jpeg, headers: ["Content-Type": "image/jpeg"])
        default:
            return reply(404, Data("no route \(method) \(path)".utf8))
        }
    }

    /// Flatbed: one page ready on the first poll, upload completed on the
    /// second. Feeder: two pages then Completed.
    private func jobDocument() -> Data {
        if adfLoaded {
            switch jobPolls {
            case 1: return Fixtures.job(state: "Processing", pre: [(1, "ReadyToUpload", "/Scan/Pages/1")], post: [])
            case 2: return Fixtures.job(state: "Processing", pre: [(2, "ReadyToUpload", "/Scan/Pages/2")], post: [(1, "UploadCompleted")])
            default: return Fixtures.job(state: "Completed", pre: [], post: [(1, "UploadCompleted"), (2, "UploadCompleted")])
            }
        }
        if jobPolls == 1 {
            return Fixtures.job(state: "Processing", pre: [(1, "ReadyToUpload", "/Scan/Pages/1")], post: [])
        }
        return Fixtures.job(state: "Processing", pre: [(1, "ReadyToUpload", "/Scan/Pages/1")], post: [(1, "UploadCompleted")])
    }
}

/// Collects written files in memory.
actor MemorySink: ScanSink {
    struct File: Sendable { let name: String; let data: Data }
    var files: [File] = []

    func write(_ data: Data, baseName: String, ext: String) async throws -> URL {
        let name = FilenamePattern.unique(base: baseName, ext: ext) { n in files.contains { $0.name == n } }
        files.append(File(name: name, data: data))
        return URL(fileURLWithPath: "/memory/\(name)")
    }

    func waitForFiles(_ count: Int, timeout: Duration = .seconds(5)) async -> [File] {
        let deadline = ContinuousClock.now + timeout
        while files.count < count, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        return files
    }
}
