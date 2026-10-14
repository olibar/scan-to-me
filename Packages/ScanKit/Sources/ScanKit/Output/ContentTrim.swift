// Finds the part of a flatbed scan that holds a small original (receipt,
// card, photo, half sheet), so it does not come out as a mostly white A4
// page. Tuned on real scans from an OfficeJet Pro 9010:
// - the lid scans as pure white; paper and print are a few levels darker,
//   so "content" is anything clearly below the page's own white level;
// - a white sheet leaves no visible outline on the white lid, so a full
//   page cannot be told apart from its text block. Trimming is therefore
//   limited to originals laid in the glass's reference corner (top left of
//   the image) that stop well short of the page width; anything else keeps
//   the full page;
// - dust on the glass shows as isolated specks and is ignored.
import CoreGraphics
import Foundation
import ImageIO

public enum ContentTrim {
    /// Longest side of the analysed copy.
    static let analysisSize = 800
    /// Content is darker than the page's white level (95th percentile) by this much.
    static let darkOffset = 9
    /// Analysis grid cell; a cell holds content when this share of it is dark.
    static let cellMillimetres = 4.0
    static let darkCellShare = 0.05
    /// Scanner frame shadows along the glass edges are ignored.
    static let edgeBandMillimetres = 2.0
    /// Content must start this close to the top-left corner (share of the page).
    static let cornerShare = 0.08
    /// Content wider than this share of the page is a full-width sheet: kept.
    static let fullWidthShare = 0.75
    /// Margin kept after the content.
    static let marginMillimetres = 3.0

    /// The rectangle to keep, in pixels of the full image with a top-left
    /// origin; nil to keep the whole page (full-width, not in the corner,
    /// blank or not decodable).
    public static func contentRect(jpeg: Data, dpi: Int) -> CGRect? {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let fullW = props[kCGImagePropertyPixelWidth] as? Int,
              let fullH = props[kCGImagePropertyPixelHeight] as? Int, fullW > 0, fullH > 0 else {
            Log.pdf.debug("trim: not a decodable image, keeping the page")
            return nil
        }
        let thumbOptions: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                             kCGImageSourceThumbnailMaxPixelSize: analysisSize]
        guard let thumb = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbOptions as CFDictionary),
              let grey = greyPixels(thumb) else {
            Log.pdf.debug("trim: could not render the analysis copy, keeping the page")
            return nil
        }
        let scale = Double(fullW) / Double(grey.width)
        let pxPerMm = Double(dpi > 0 ? dpi : 300) / 25.4 / scale
        guard let box = contentBounds(grey, pxPerMm: pxPerMm) else {
            Log.pdf.debug("trim: no content found, keeping the page")
            return nil
        }
        let w = Double(grey.width), h = Double(grey.height)
        let inCorner = box.minX <= w * cornerShare && box.minY <= h * cornerShare
        guard inCorner, box.maxX < w * fullWidthShare else {
            Log.pdf.debug("trim: content \(Int(box.minX * 100 / w))-\(Int(box.maxX * 100 / w))% x \(Int(box.minY * 100 / h))-\(Int(box.maxY * 100 / h))% corner=\(inCorner), keeping \(fullW)x\(fullH)")
            return nil
        }
        let margin = marginMillimetres * pxPerMm
        let rect = CGRect(x: 0, y: 0, width: min(w, box.maxX + margin) * scale, height: min(h, box.maxY + margin) * scale)
            .integral.intersection(CGRect(x: 0, y: 0, width: fullW, height: fullH))
        Log.pdf.debug("trim: \(fullW)x\(fullH) -> \(Int(rect.width))x\(Int(rect.height))")
        return rect
    }

    /// Re-encodes the kept part of a JPEG. Returns the input when it cannot.
    public static func croppedJPEG(_ jpeg: Data, to rect: CGRect, quality: Double = 0.92) -> Data {
        guard let source = CGImageSourceCreateWithData(jpeg as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let cropped = image.cropping(to: rect) else { return jpeg }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, "public.jpeg" as CFString, 1, nil) else { return jpeg }
        CGImageDestinationAddImage(dest, cropped, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return jpeg }
        Log.pdf.debug("trim: jpeg \(jpeg.count) -> \(out.length) bytes")
        return out as Data
    }

    struct Grey {
        let width: Int
        let height: Int
        let pixels: [UInt8]
    }

    /// 8-bit grey copy; row 0 is the top of the image.
    static func greyPixels(_ image: CGImage) -> Grey? {
        let w = image.width, h = image.height
        var pixels = [UInt8](repeating: 255, count: w * h)
        let ok = pixels.withUnsafeMutableBytes { buf -> Bool in
            guard let ctx = CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w,
                                      space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue) else {
                return false
            }
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        return ok ? Grey(width: w, height: h, pixels: pixels) : nil
    }

    /// Bounding box of the content cells of the analysis copy, in its
    /// pixels: cells with enough pixels darker than the page's white level,
    /// minus isolated cells (dust). Nil when there is none.
    static func contentBounds(_ g: Grey, pxPerMm: Double) -> CGRect? {
        let band = Int((edgeBandMillimetres * pxPerMm).rounded(.up))
        let cell = max(2, Int((cellMillimetres * pxPerMm).rounded()))
        let white = Int(g.pixels.sorted()[g.pixels.count * 19 / 20])
        let threshold = white - darkOffset
        let gw = (g.width + cell - 1) / cell, gh = (g.height + cell - 1) / cell
        var dark = [Bool](repeating: false, count: gw * gh)
        for gy in 0..<gh {
            for gx in 0..<gw {
                // Cells in the edge band have an empty range: skip them.
                let y0 = max(band, gy * cell), y1 = min(g.height - band, gy * cell + cell)
                let x0 = max(band, gx * cell), x1 = min(g.width - band, gx * cell + cell)
                guard y0 < y1, x0 < x1 else { continue }
                var n = 0, total = 0
                for y in y0..<y1 {
                    for x in x0..<x1 {
                        total += 1
                        if Int(g.pixels[y * g.width + x]) < threshold { n += 1 }
                    }
                }
                dark[gy * gw + gx] = total > 0 && Double(n) >= Double(total) * darkCellShare
            }
        }
        var minX = gw, minY = gh, maxX = -1, maxY = -1
        for gy in 0..<gh {
            for gx in 0..<gw where dark[gy * gw + gx] && hasDarkNeighbour(dark, gw, gh, gx, gy) {
                minX = min(minX, gx); minY = min(minY, gy); maxX = max(maxX, gx); maxY = max(maxY, gy)
            }
        }
        guard maxX >= 0 else { return nil }
        return CGRect(x: minX * cell, y: minY * cell,
                      width: min(g.width, (maxX + 1) * cell) - minX * cell,
                      height: min(g.height, (maxY + 1) * cell) - minY * cell)
    }

    /// Another content cell within two cells; a lone one is a speck of dust.
    private static func hasDarkNeighbour(_ dark: [Bool], _ gw: Int, _ gh: Int, _ gx: Int, _ gy: Int) -> Bool {
        for dy in -2...2 {
            for dx in -2...2 where dx != 0 || dy != 0 {
                let x = gx + dx, y = gy + dy
                if x >= 0, y >= 0, x < gw, y < gh, dark[y * gw + x] { return true }
            }
        }
        return false
    }
}
