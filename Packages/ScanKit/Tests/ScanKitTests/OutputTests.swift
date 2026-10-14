import Testing
import Foundation
@testable import ScanKit

struct JPEGInfoTests {
    @Test func baselineGray() throws {
        let info = try JPEGInfo.parse(Fixtures.jpeg(width: 20, height: 30, components: 1))
        #expect(info == JPEGInfo(width: 20, height: 30, components: 1))
    }

    @Test func progressiveColor() throws {
        let info = try JPEGInfo.parse(Fixtures.jpeg(width: 640, height: 480, components: 3, progressive: true))
        #expect(info.width == 640)
        #expect(info.height == 480)
        #expect(info.components == 3)
    }

    @Test func truncatedThrows() {
        #expect(throws: (any Error).self) { try JPEGInfo.parse(Data([0xFF, 0xD8, 0xFF, 0xC0, 0x00])) }
        #expect(throws: (any Error).self) { try JPEGInfo.parse(Data("not a jpeg".utf8)) }
    }
}

struct PDFWriterTests {
    @Test func twoPages() throws {
        let pages = [PDFWriter.Page(jpeg: Fixtures.jpeg(width: 300, height: 600, components: 3), dpi: 300),
                     PDFWriter.Page(jpeg: Fixtures.jpeg(width: 150, height: 150, components: 1), dpi: 150)]
        let pdf = try PDFWriter.write(pages)
        let s = String(decoding: pdf, as: UTF8.self)
        #expect(s.hasPrefix("%PDF-1.4\n"))
        #expect(s.hasSuffix("%%EOF\n"))
        #expect(s.contains("/Count 2"))
        #expect(s.contains("/Kids [3 0 R 6 0 R ]"))
        #expect(s.contains("/MediaBox [0 0 72.00 144.00]"))
        #expect(s.contains("/MediaBox [0 0 72.00 72.00]"))
        #expect(s.components(separatedBy: "/DCTDecode").count - 1 == 2)
        #expect(s.contains("/DeviceRGB"))
        #expect(s.contains("/DeviceGray"))
        #expect(s.contains("xref\n0 9\n"))
    }

    @Test func xrefOffsetsPointAtObjects() throws {
        let pdf = try PDFWriter.write([PDFWriter.Page(jpeg: Fixtures.jpeg(width: 10, height: 10, components: 3), dpi: 72)])
        let s = String(decoding: pdf, as: UTF8.self)
        let xrefStart = Int(s.components(separatedBy: "startxref\n")[1].components(separatedBy: "\n")[0])!
        #expect(s[s.index(s.startIndex, offsetBy: xrefStart)...].hasPrefix("xref"))
        let lines = s[s.index(s.startIndex, offsetBy: xrefStart)...].components(separatedBy: "\n")
        for (i, line) in lines.dropFirst(3).prefix(5).enumerated() {
            let off = Int(line.prefix(10))!
            #expect(s[s.index(s.startIndex, offsetBy: off)...].hasPrefix("\(i + 1) 0 obj"), "object \(i + 1)")
        }
    }

    @Test func emptyThrows() {
        #expect(throws: (any Error).self) { try PDFWriter.write([]) }
    }
}

struct FilenamePatternTests {
    @Test func render() {
        let date = Date(timeIntervalSince1970: 1_700_000_000) // 2023-11-14 22:13:20 UTC
        let name = FilenamePattern.render("scan_{date}_{time}_{page}", date: date, page: 3, timeZone: TimeZone(identifier: "UTC")!)
        #expect(name == "scan_2023-11-14_221320_03")
    }

    @Test func unique() {
        let taken: Set<String> = ["scan.pdf", "scan-1.pdf"]
        #expect(FilenamePattern.unique(base: "scan", ext: "pdf") { taken.contains($0) } == "scan-2.pdf")
        #expect(FilenamePattern.unique(base: "x", ext: "jpg") { _ in false } == "x.jpg")
    }

    @Test func sanitize() {
        #expect(FilenamePattern.sanitize("a/b:c") == "a_b_c")
        #expect(FilenamePattern.sanitize("") == "scan")
    }
}

struct FolderScanSinkTests {
    @Test func writesUniqueAtomicFiles() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scantome-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sink = FolderScanSink(directory: dir)
        let a = try await sink.write(Data("one".utf8), baseName: "scan", ext: "pdf")
        let b = try await sink.write(Data("two".utf8), baseName: "scan", ext: "pdf")
        #expect(a.lastPathComponent == "scan.pdf")
        #expect(b.lastPathComponent == "scan-1.pdf")
        #expect(try Data(contentsOf: b) == Data("two".utf8))
        let listing = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        #expect(listing == ["scan-1.pdf", "scan.pdf"])
    }

    @Test func concurrentWritesGetDistinctNames() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("scantome-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let sink = FolderScanSink(directory: dir)
        let urls = await withTaskGroup(of: URL?.self) { group in
            for i in 0..<8 {
                group.addTask { try? await sink.write(Data("\(i)".utf8), baseName: "same", ext: "jpg") }
            }
            var out: [URL] = []
            for await u in group { if let u { out.append(u) } }
            return out
        }
        #expect(Set(urls.map(\.lastPathComponent)).count == 8)
    }
}
