// sample_scans.swift - sample files for the App Store screenshots: a
// receipt-sized PDF (the one previewed), a two-page A4 PDF and a JPEG.
// Content is invented; no real business, person or card number.
//
// Usage: swift sample_scans.swift <output-dir>
// Writes receipt.pdf, letter.pdf and photo.jpg into <output-dir>.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let outDir = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")
let mm: CGFloat = 72 / 25.4

func text(_ ctx: CGContext, _ s: String, x: CGFloat, y: CGFloat, size: CGFloat, bold: Bool = false,
          mono: Bool = true, gray: CGFloat = 0.12, align: CTTextAlignment = .left, width: CGFloat = 0) {
    let name = mono ? (bold ? "Menlo-Bold" : "Menlo-Regular") : (bold ? "Helvetica-Bold" : "Helvetica")
    let font = CTFontCreateWithName(name as CFString, size, nil)
    let color = CGColor(gray: gray, alpha: 1)
    let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: color]
    let line = CTLineCreateWithAttributedString(CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary))
    var px = x
    if align != .left {
        let w = CTLineGetTypographicBounds(line, nil, nil, nil)
        px = align == .right ? x + width - CGFloat(w) : x + (width - CGFloat(w)) / 2
    }
    ctx.textPosition = CGPoint(x: px, y: y)
    CTLineDraw(line, ctx)
}

func pdf(_ name: String, pages: [(CGSize, (CGContext, CGSize) -> Void)]) {
    var box = CGRect(origin: .zero, size: pages[0].0)
    let ctx = CGContext(outDir.appendingPathComponent(name) as CFURL, mediaBox: &box, nil)!
    for (size, draw) in pages {
        var pageBox = CGRect(origin: .zero, size: size)
        ctx.beginPage(mediaBox: &pageBox)
        ctx.setFillColor(CGColor(gray: 0.985, alpha: 1))
        ctx.fill(pageBox)
        draw(ctx, size)
        ctx.endPage()
    }
    ctx.closePDF()
    print("sample-scans: wrote \(name)")
}

// Receipt, 80 x 105 mm: what "Trim empty margins" keeps of a receipt on A4 glass.
let receipt = CGSize(width: 80 * mm, height: 105 * mm)
pdf("receipt.pdf", pages: [(receipt, { ctx, s in
    let left = 7 * mm, w = s.width - 14 * mm
    var y = s.height - 16 * mm
    func row(_ l: String, _ r: String, bold: Bool = false) {
        text(ctx, l, x: left, y: y, size: 8.5, bold: bold)
        text(ctx, r, x: left, y: y, size: 8.5, bold: bold, align: .right, width: w)
        y -= 5.2 * mm
    }
    text(ctx, "THE CORNER CAFE", x: left, y: y, size: 12, bold: true, align: .center, width: w); y -= 6 * mm
    text(ctx, "12 Harbour Street", x: left, y: y, size: 8, align: .center, width: w); y -= 4.2 * mm
    text(ctx, "Table 4 - 14/10/2026 08:42", x: left, y: y, size: 8, align: .center, width: w); y -= 9 * mm
    row("1 Flat white", "4.50")
    row("1 Croissant", "3.20")
    row("1 Orange juice", "5.00")
    row("1 Granola bowl", "8.90")
    y -= 1.5 * mm
    ctx.setStrokeColor(CGColor(gray: 0.3, alpha: 1)); ctx.setLineDash(phase: 0, lengths: [2, 2])
    ctx.move(to: CGPoint(x: left, y: y + 3 * mm)); ctx.addLine(to: CGPoint(x: left + w, y: y + 3 * mm)); ctx.strokePath()
    y -= 2 * mm
    row("TOTAL", "21.60", bold: true)
    row("Paid by card", "21.60")
    y -= 8 * mm
    text(ctx, "Thank you, see you soon!", x: left, y: y, size: 8, align: .center, width: w)
})])

// A two-page A4 letter: grey text blocks, only its name shows in the list.
let a4 = CGSize(width: 210 * mm, height: 297 * mm)
func letterPage(_ ctx: CGContext, _ s: CGSize) {
    ctx.setFillColor(CGColor(gray: 0.55, alpha: 1))
    var y = s.height - 40 * mm
    for i in 0..<34 {
        let w = (i % 7 == 6) ? 90 * mm : 160 * mm
        ctx.fill(CGRect(x: 25 * mm, y: y, width: w, height: 2.2 * mm))
        y -= (i % 7 == 6) ? 10 * mm : 6 * mm
    }
}
pdf("letter.pdf", pages: [(a4, letterPage), (a4, letterPage)])

// A small "photo" JPEG.
let photoCtx = CGContext(data: nil, width: 1200, height: 800, bitsPerComponent: 8, bytesPerRow: 0,
                         space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let sky = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!,
                     colors: [CGColor(red: 0.98, green: 0.78, blue: 0.55, alpha: 1), CGColor(red: 0.35, green: 0.55, blue: 0.85, alpha: 1)] as CFArray,
                     locations: [0, 1])!
photoCtx.drawLinearGradient(sky, start: CGPoint(x: 0, y: 0), end: CGPoint(x: 0, y: 800), options: [])
photoCtx.setFillColor(CGColor(red: 0.2, green: 0.32, blue: 0.3, alpha: 1))
photoCtx.fill(CGRect(x: 0, y: 0, width: 1200, height: 260))
let dest = CGImageDestinationCreateWithURL(outDir.appendingPathComponent("photo.jpg") as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, photoCtx.makeImage()!, nil)
CGImageDestinationFinalize(dest)
print("sample-scans: wrote photo.jpg")
