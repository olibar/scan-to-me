// Assembles JPEG page images into a minimal PDF without external
// dependencies. Each JPEG is embedded as-is using DCTDecode.
import CoreGraphics
import Foundation

public enum PDFWriter {
    /// One scanned page: raw JPEG bytes, the DPI it was scanned at, and
    /// optionally the part to show (pixels, top-left origin). A crop only
    /// shrinks the page around the image; the JPEG is embedded unchanged.
    public struct Page: Sendable {
        public var jpeg: Data
        public var dpi: Int
        public var crop: CGRect?

        public init(jpeg: Data, dpi: Int, crop: CGRect? = nil) {
            self.jpeg = jpeg
            self.dpi = dpi
            self.crop = crop
        }
    }

    /// Emits a PDF with one page per JPEG, sized so the image prints at its
    /// native DPI.
    public static func write(_ pages: [Page]) throws -> Data {
        Log.pdf.debug("pdf: writing pages=\(pages.count)")
        guard !pages.isEmpty else { throw LEDMError.invalidResponse("pdf: no pages to write") }
        var out = Data()
        var offsets: [Int] = []
        func obj(_ body: (inout Data) throws -> Void) rethrows {
            offsets.append(out.count)
            out.append(ascii("\(offsets.count) 0 obj\n"))
            try body(&out)
            out.append(ascii("\nendobj\n"))
        }
        out.append(ascii("%PDF-1.4\n%"))
        out.append(contentsOf: [0xE2, 0xE3, 0xCF, 0xD3, 0x0A])
        // Object numbering: 1 catalog, 2 pages, then per page: page, image, content.
        obj { $0.append(ascii("<< /Type /Catalog /Pages 2 0 R >>")) }
        let kids = pages.indices.map { "\(3 + $0 * 3) 0 R " }.joined()
        obj { $0.append(ascii("<< /Type /Pages /Kids [\(kids)] /Count \(pages.count) >>")) }
        for (i, page) in pages.enumerated() {
            let info: JPEGInfo
            do {
                info = try JPEGInfo.parse(page.jpeg)
            } catch {
                throw LEDMError.parse("pdf page \(i + 1): \(error)")
            }
            let dpi = page.dpi > 0 ? page.dpi : 300
            let ptPerPx = 72 / Double(dpi)
            let wPt = Double(info.width) * ptPerPx
            let hPt = Double(info.height) * ptPerPx
            // Page box and image offset: the whole image, or the cropped part
            // (PDF y grows upwards, the crop's from the top).
            var box = (w: wPt, h: hPt, dx: 0.0, dy: 0.0)
            if let c = page.crop, c.width > 0, c.height > 0 {
                box = (w: c.width * ptPerPx, h: c.height * ptPerPx,
                       dx: -c.minX * ptPerPx, dy: -(Double(info.height) - c.maxY) * ptPerPx)
            }
            let cs = info.components == 1 ? "/DeviceGray" : (info.components == 4 ? "/DeviceCMYK" : "/DeviceRGB")
            Log.pdf.debug("pdf: page \(i + 1) \(info.width)x\(info.height) dpi=\(dpi) colorspace=\(cs)")
            let pageObj = 3 + i * 3
            let imgObj = pageObj + 1
            obj {
                $0.append(ascii("<< /Type /Page /Parent 2 0 R /MediaBox [0 0 \(fmt(box.w)) \(fmt(box.h))] "
                    + "/Resources << /XObject << /Im0 \(imgObj) 0 R >> >> /Contents \(imgObj + 1) 0 R >>"))
            }
            obj {
                $0.append(ascii("<< /Type /XObject /Subtype /Image /Width \(info.width) /Height \(info.height) /ColorSpace \(cs) "
                    + "/BitsPerComponent 8 /Filter /DCTDecode /Length \(page.jpeg.count) >>\nstream\n"))
                $0.append(page.jpeg)
                $0.append(ascii("\nendstream"))
            }
            let content = "q \(fmt(wPt)) 0 0 \(fmt(hPt)) \(fmt(box.dx)) \(fmt(box.dy)) cm /Im0 Do Q"
            obj { $0.append(ascii("<< /Length \(content.utf8.count) >>\nstream\n\(content)\nendstream")) }
        }
        let xref = out.count
        out.append(ascii("xref\n0 \(offsets.count + 1)\n0000000000 65535 f \n"))
        for off in offsets {
            out.append(ascii(String(format: "%010d 00000 n \n", off)))
        }
        out.append(ascii("trailer\n<< /Size \(offsets.count + 1) /Root 1 0 R >>\nstartxref\n\(xref)\n%%EOF\n"))
        Log.pdf.debug("pdf: written bytes=\(out.count)")
        return out
    }

    private static func ascii(_ s: String) -> Data { Data(s.utf8) }

    private static func fmt(_ v: Double) -> String { String(format: "%.2f", locale: nil, v) }
}
