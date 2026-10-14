// Telling identical printers apart and reporting absent ones as such.
import Foundation
import Network
import Testing
@testable import ScanKit

struct PrinterIdentityTests {
    private let home = PrinterRecord(displayName: "Home", serviceName: "HP OfficeJet Pro 9010 series [7F6462]",
                                     uuid: "c76dc8e1-c9d0-5eef-35a2-609e5b3a7ee6", host: "192.168.1.20")
    private let office = PrinterRecord(displayName: "Office", serviceName: "HP OfficeJet Pro 9010 series [0A1B2C]",
                                       uuid: "11111111-2222-3333-4444-555555555555", host: "192.168.1.20")

    private func scanner(_ name: String, uuid: String?) -> DiscoveredScanner {
        DiscoveredScanner(serviceName: name, model: "HP OfficeJet Pro 9010 series", mfg: "HP", uuid: uuid,
                          endpoint: .hostPort(host: "192.168.1.20", port: 8080))
    }

    @Test func identicalModelsOnTheSameAddressAreDifferentPrinters() {
        #expect(!home.isSamePrinter(as: office))
        var again = home
        again.id = UUID()
        again.host = "10.0.0.7"
        #expect(home.isSamePrinter(as: again))
    }

    @Test func manualPrintersCompareByAddress() {
        let a = PrinterRecord(displayName: "a", host: "10.0.0.5", port: 8080)
        let b = PrinterRecord(displayName: "b", host: "10.0.0.5", port: 8080)
        #expect(a.isSamePrinter(as: b))
        #expect(!a.isSamePrinter(as: home))
    }

    @Test func discoveredServiceMatchesByUUIDThenName() {
        #expect(home.matches(scanner("HP OfficeJet Pro 9010 series [7F6462]", uuid: "C76DC8E1-C9D0-5EEF-35A2-609E5B3A7EE6")))
        #expect(!office.matches(scanner("HP OfficeJet Pro 9010 series [7F6462]", uuid: "c76dc8e1-c9d0-5eef-35a2-609e5b3a7ee6")))
        #expect(home.matches(scanner("hp officejet pro 9010 series [7f6462]", uuid: nil)))
        #expect(!PrinterRecord(displayName: "m", host: "192.168.1.20").matches(scanner("x", uuid: nil)))
    }

    @Test func stateSavedBeforeUUIDsStillDecodes() throws {
        let json = #"{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","displayName":"Home","serviceName":"s","host":"h","port":8080}"#
        let record = try JSONDecoder().decode(PrinterRecord.self, from: Data(json.utf8))
        #expect(record.uuid == nil && record.isBonjour)
    }
}

/// A printer that is not on this network: every request fails to connect.
struct AbsentPrinter: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw URLError(.cannotConnectToHost)
    }
}

struct UnreachableSessionTests {
    @Test func classification() {
        #expect(PrinterSession.isUnreachable(URLError(.timedOut)))
        #expect(PrinterSession.isUnreachable(LEDMError.unreachable("x")))
        #expect(!PrinterSession.isUnreachable(URLError(.badServerResponse)))
        #expect(!PrinterSession.isUnreachable(LEDMError.parse("x")))
    }

    @Test func absentPrinterIsReportedAsUnreachable() async {
        let prefs = ScanPreferences.defaults(deviceName: "Test Phone")
        let record = PrinterRecord(displayName: "Office", host: "192.168.1.20", port: 8080)
        let session = PrinterSession(printer: record, preferences: prefs, sink: MemorySink(), transport: AbsentPrinter())
        let task = Task { await session.run() }
        let deadline = ContinuousClock.now + .seconds(5)
        while await session.lastStatus != .unreachable, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(await session.lastStatus == .unreachable)
        task.cancel()
        _ = await task.value
    }
}
