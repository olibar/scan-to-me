// Trimming the empty margins around small originals, on real JPEGs drawn
// with CoreGraphics.
import CoreGraphics
import Foundation
import ImageIO
import Testing
@testable import ScanKit

enum ScanImage {
    /// A white "glass" of A4 at `dpi`, with dark rectangles (pixels, top-left
    /// origin) drawn on it, encoded as JPEG.
    static func jpeg(dpi: Int = 100, marks: [CGRect]) -> Data {
        let w = 2481 * dpi / 300, h = 3507 * dpi / 300
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue)!
        ctx.setFillColor(gray: 0.98, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        ctx.setFillColor(gray: 0.2, alpha: 1)
        for m in marks {
            ctx.fill(CGRect(x: m.minX, y: CGFloat(h) - m.maxY, width: m.width, height: m.height))
        }
        let out = NSMutableData()
        let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, ctx.makeImage()!, [kCGImageDestinationLossyCompressionQuality: 0.9] as CFDictionary)
        CGImageDestinationFinalize(dest)
        return out as Data
    }

    static func size(_ jpeg: Data) -> (Int, Int) {
        let src = CGImageSourceCreateWithData(jpeg as CFData, nil)!
        let p = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as! [CFString: Any]
        return (p[kCGImagePropertyPixelWidth] as! Int, p[kCGImagePropertyPixelHeight] as! Int)
    }
}

struct ContentTrimTests {
    // At 100 dpi an A4 glass is 827x1169 px; 3 mm of margin is about 12 px.
    @Test func originalInTheCornerIsTrimmedFromTheCorner() throws {
        let card = CGRect(x: 0, y: 0, width: 340, height: 215)
        let rect = try #require(ContentTrim.contentRect(jpeg: ScanImage.jpeg(marks: [card]), dpi: 100))
        #expect(rect.minX == 0 && rect.minY == 0)
        #expect(rect.width >= 340 && rect.width < 375 && rect.height >= 215 && rect.height < 250)
    }

    @Test func receiptIsTrimmedToItsWidthAndLength() throws {
        let receipt = CGRect(x: 0, y: 0, width: 300, height: 700)
        let rect = try #require(ContentTrim.contentRect(jpeg: ScanImage.jpeg(marks: [receipt]), dpi: 100))
        #expect(rect.width < 335 && rect.height >= 700 && rect.height < 735)
    }

    @Test func originalAwayFromTheCornerKeepsThePage() {
        let card = CGRect(x: 300, y: 400, width: 340, height: 215)
        #expect(ContentTrim.contentRect(jpeg: ScanImage.jpeg(marks: [card]), dpi: 100) == nil)
    }

    @Test func fullWidthSheetsKeepThePage() {
        // A letter with margins, and a short letter whose lines start near
        // the corner: both are as wide as an A4 page, so they stay A4.
        let letter = (0..<20).map { CGRect(x: 80, y: 70 + $0 * 50, width: 670, height: 12) }
        #expect(ContentTrim.contentRect(jpeg: ScanImage.jpeg(marks: letter), dpi: 100) == nil)
        let short = (0..<6).map { CGRect(x: 30, y: 30 + $0 * 40, width: 720, height: 12) }
        #expect(ContentTrim.contentRect(jpeg: ScanImage.jpeg(marks: short), dpi: 100) == nil)
    }

    @Test func blankAndUndecodablePagesAreLeftAlone() {
        #expect(ContentTrim.contentRect(jpeg: ScanImage.jpeg(marks: []), dpi: 100) == nil)
        #expect(ContentTrim.contentRect(jpeg: Fixtures.jpeg(width: 30, height: 40, components: 3), dpi: 300) == nil)
    }

    @Test func dustOnTheGlassIsIgnored() throws {
        let card = CGRect(x: 0, y: 0, width: 340, height: 215)
        let specks = [CGRect(x: 60, y: 980, width: 2, height: 2), CGRect(x: 120, y: 1000, width: 1, height: 2)]
        let rect = try #require(ContentTrim.contentRect(jpeg: ScanImage.jpeg(marks: [card] + specks), dpi: 100))
        #expect(rect.height < 250)
    }

    @Test func croppedJPEGHasTheRectSize() {
        let jpeg = ScanImage.jpeg(marks: [CGRect(x: 300, y: 400, width: 340, height: 215)])
        let out = ContentTrim.croppedJPEG(jpeg, to: CGRect(x: 288, y: 388, width: 364, height: 239))
        #expect(ScanImage.size(out) == (364, 239))
    }

    @Test func pdfPageShrinksAroundTheUnchangedImage() throws {
        let jpeg = Fixtures.jpeg(width: 827, height: 1169, components: 1)
        let page = PDFWriter.Page(jpeg: jpeg, dpi: 100, crop: CGRect(x: 100, y: 200, width: 300, height: 150))
        let pdf = String(decoding: try PDFWriter.write([page]), as: UTF8.self)
        // 300x150 px at 100 dpi = 216x108 pt; the image keeps its full size,
        // shifted left by 72 pt and down by (1169 - 350) px = 589.68 pt.
        #expect(pdf.contains("/MediaBox [0 0 216.00 108.00]"))
        #expect(pdf.contains("q 595.44 0 0 841.68 -72.00 -589.68 cm /Im0 Do Q"))
        #expect(pdf.contains("/Width 827 /Height 1169"))
    }

    @Test func settingsSavedBeforeTrimmingStillLoad() throws {
        let old = #"{"destinationName":"Phone","format":"pdf","resolution":300,"colorMode":"color","paper":"a4","filenamePattern":"scan_{date}","pageTimeout":120,"saveJPEGToPhotos":true}"#
        let p = try JSONDecoder().decode(ScanPreferences.self, from: Data(old.utf8))
        #expect(p.trimMargins && p.saveJPEGToPhotos && p.destinationName == "Phone")
    }
}
