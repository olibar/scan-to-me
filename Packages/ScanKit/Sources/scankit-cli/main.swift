// Command-line harness for ScanKit on macOS: validates discovery and the
// full scan-to-computer loop against a real printer without Xcode.
//
//   scankit-cli discover
//   scankit-cli serve <host[:port]> [--name <name>] [--out <dir>] [--format pdf|jpeg]
import Foundation
import ScanKit

func usage() -> Never {
    FileHandle.standardError.write(Data("""
    usage:
      scankit-cli discover
      scankit-cli serve <host[:port]> [--name <name>] [--out <dir>] [--format pdf|jpeg] [--resolution <dpi>]

    """.utf8))
    exit(2)
}

func option(_ name: String, in args: [String]) -> String? {
    guard let i = args.firstIndex(of: name), i + 1 < args.count else { return nil }
    return args[i + 1]
}

func discover() async {
    print("browsing \(ScannerBrowser.serviceTypes.joined(separator: ", ")) for 5 seconds...")
    let latest = await withTaskGroup(of: [DiscoveredScanner].self) { group in
        group.addTask {
            var last: [DiscoveredScanner] = []
            for await list in ScannerBrowser.browse() { last = list }
            return last
        }
        group.addTask {
            try? await Task.sleep(for: .seconds(5))
            return []
        }
        let first = await group.next() ?? []
        group.cancelAll()
        let second = await group.next() ?? []
        return first.isEmpty ? second : first
    }
    if latest.isEmpty {
        print("no scanners found")
        return
    }
    for s in latest {
        var addr = "?"
        if let r = try? await EndpointResolver.resolve(s.endpoint) { addr = "\(r.host):\(r.port)" }
        print("\(s.isHP ? "*" : " ") \(s.serviceName)  \(addr)  \(s.model ?? "")")
    }
}

func serve(_ args: [String]) async {
    guard let target = args.first else { usage() }
    var host = target
    var port = 8080
    if let colon = target.lastIndex(of: ":"), let p = Int(target[target.index(after: colon)...]) {
        host = String(target[..<colon])
        port = p
    }
    let name = option("--name", in: args) ?? ProcessInfo.processInfo.hostName
    let out = URL(fileURLWithPath: option("--out", in: args) ?? "Scans", isDirectory: true)
    var prefs = ScanPreferences.defaults(deviceName: name)
    if let f = option("--format", in: args), let format = OutputFormat(rawValue: f) { prefs.format = format }
    if let r = option("--resolution", in: args), let res = Int(r) { prefs.resolution = res }
    do { try prefs.validate() } catch { print("invalid settings: \(error)"); exit(2) }

    let printer = PrinterRecord(displayName: host, host: host, port: port)
    let session = PrinterSession(printer: printer, preferences: prefs, sink: FolderScanSink(directory: out))
    print("serving \(host):\(port) as \"\(name)\", saving to \(out.path); Ctrl-C to stop")
    let runner = Task { await session.run() }
    signal(SIGINT, SIG_IGN)
    let sig = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
    sig.setEventHandler {
        print("\nstopping...")
        runner.cancel()
    }
    sig.resume()
    for await event in session.events {
        switch event {
        case let .status(s): print("status: \(s)")
        case let .log(e): print("[\(e.level.rawValue)] \(e.message)")
        case let .saved(s): print("saved: \(s.url.path) (\(s.pages) pages, \(s.format.rawValue))")
        case let .addressChanged(h, p): print("address changed: \(h):\(p)")
        }
    }
    await runner.value
}

let args = Array(CommandLine.arguments.dropFirst())
switch args.first {
case "discover": await discover()
case "serve": await serve(Array(args.dropFirst()))
default: usage()
}
