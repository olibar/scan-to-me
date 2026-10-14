// make-icon.swift - generates the Scan to Me app icon (design A of the
// October 2026 review: balanced margins, one 44 px stroke weight, a gap where
// the page crosses the phone frame).
//
// Usage, from the repository root:  swift design/make-icon.swift
//
// Writes ScanToMe/Assets.xcassets/AppIcon.appiconset/AppIcon.png (1024x1024,
// opaque RGB, square: iOS applies the corner mask) and prints the glyph's
// bounding box and margins. Only CoreGraphics and ImageIO are used.
// All geometry is expressed on the 1024 canvas with y pointing DOWN.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let canvas: CGFloat = 1024
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!
let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    .appendingPathComponent("ScanToMe/Assets.xcassets/AppIcon.appiconset/AppIcon.png")

// MARK: - Palette

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [
        CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
        CGFloat(hex & 0xFF) / 255, a,
    ])!
}

let blueTop = rgb(0x0A93E4)     // top-left
let blueBottom = rgb(0x005DAA)  // bottom-right
let white = rgb(0xFFFFFF)

// MARK: - Bitmap helpers

/// Opaque RGB context (no alpha channel in the PNG). Origin top-left, y down.
func opaqueContext(_ size: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    flip(ctx, CGFloat(size))
    return ctx
}

/// RGBA context used for the white glyph layer so that cut-outs can be erased.
func layerContext(_ size: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    flip(ctx, CGFloat(size))
    return ctx
}

func flip(_ ctx: CGContext, _ h: CGFloat) {
    ctx.translateBy(x: 0, y: h)
    ctx.scaleBy(x: 1, y: -1)
}

func writePNG(_ image: CGImage, to url: URL) {
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("make-icon: cannot create \(url.path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) { fatalError("make-icon: cannot write \(url.path)") }
    print("make-icon: wrote \(url.path) (\(image.width)x\(image.height))")
}

// MARK: - Shape helpers (y down)

func rrect(_ r: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

/// Page with a cut top-right corner of size `fold`, small rounding on the other corners.
func pagePath(_ r: CGRect, fold: CGFloat, corner: CGFloat = 14) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.minX + corner, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX - fold, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + fold))
    p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: corner)
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: corner)
    p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: corner)
    p.closeSubpath()
    return p
}

/// The small triangle that suggests the folded-over corner.
func foldPath(_ r: CGRect, fold: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: r.maxX - fold, y: r.minY))
    p.addLine(to: CGPoint(x: r.maxX - fold, y: r.minY + fold))
    p.addLine(to: CGPoint(x: r.maxX, y: r.minY + fold))
    p.closeSubpath()
    return p
}

func strokeLine(_ ctx: CGContext, _ pts: [CGPoint], width: CGFloat) {
    ctx.setLineWidth(width)
    ctx.setLineCap(.round)
    ctx.setLineJoin(.round)
    ctx.beginPath()
    ctx.addLines(between: pts)
    ctx.strokePath()
}

/// Down arrow: shaft from `top` to `tip`, chevron of half-width `half`, rounded caps/joins.
func arrow(_ ctx: CGContext, cx: CGFloat, top: CGFloat, tip: CGFloat, half: CGFloat, width: CGFloat) {
    strokeLine(ctx, [CGPoint(x: cx, y: top), CGPoint(x: cx, y: tip)], width: width)
    strokeLine(ctx, [CGPoint(x: cx - half, y: tip - half), CGPoint(x: cx, y: tip),
                     CGPoint(x: cx + half, y: tip - half)], width: width)
}

/// Switch the layer to "erase" mode for knock-outs (lets the background show through).
func erase(_ ctx: CGContext, _ body: () -> Void) {
    ctx.saveGState()
    ctx.setBlendMode(.clear)
    body()
    ctx.restoreGState()
}

// MARK: - Icon composition

/// Background gradient plus the white glyph drawn by `glyph` into a transparent layer.
func renderIcon(_ glyph: (CGContext) -> Void) -> CGImage {
    let size = Int(canvas)
    let layer = layerContext(size)
    layer.setFillColor(white)
    layer.setStrokeColor(white)
    glyph(layer)
    let glyphImage = layer.makeImage()!

    let ctx = opaqueContext(size)
    let grad = CGGradient(colorsSpace: srgb, colors: [blueTop, blueBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: canvas, y: canvas), options: [])
    // Layer is already y-down; undo the flip for the image draw.
    ctx.saveGState()
    flip(ctx, canvas)
    ctx.draw(glyphImage, in: CGRect(x: 0, y: 0, width: canvas, height: canvas))
    ctx.restoreGState()
    return ctx.makeImage()!
}

// The glyph: same composition as the 1.0 icon, re-proportioned.
// Wider/shorter phone, document lowered so it clears the top, a real gap where the page
// crosses the phone outline, one stroke weight (44) everywhere, rounded arrow tip.
func glyph(_ c: CGContext) {
    let s: CGFloat = 44
    let phone = CGRect(x: 252, y: 300, width: 520, height: 594)    // outer edge
    let page = CGRect(x: 362, y: 130, width: 300, height: 330)
    let gap: CGFloat = 26

    c.addPath(rrect(phone.insetBy(dx: s / 2, dy: s / 2), 118 - s / 2))
    c.setLineWidth(s)
    c.strokePath()
    // Gap around the page where it crosses the phone frame.
    erase(c) {
        c.addPath(pagePath(page.insetBy(dx: -gap, dy: -gap), fold: 86 + gap * 0.4, corner: 14 + gap))
        c.fillPath()
    }
    c.addPath(pagePath(page, fold: 86))
    c.fillPath()
    erase(c) {
        // Text lines.
        let x0 = page.minX + 46, x1 = page.maxX - 58
        for y in [222.0, 276.0, 330.0] {
            strokeLine(c, [CGPoint(x: x0, y: y), CGPoint(x: x1, y: y)], width: 22)
        }
        strokeLine(c, [CGPoint(x: x0, y: 384), CGPoint(x: x0 + 120, y: 384)], width: 22)
    }
    arrow(c, cx: 512, top: 528, tip: 724, half: 92, width: s)
    strokeLine(c, [CGPoint(x: 452, y: 818), CGPoint(x: 572, y: 818)], width: 30)
}

// MARK: - Measurement

struct Margins: CustomStringConvertible {
    let minX: Int, minY: Int, maxX: Int, maxY: Int, size: Int
    var description: String {
        let s = Double(size)
        let l = minX, t = minY, r = size - 1 - maxX, b = size - 1 - maxY
        func pct(_ v: Int) -> String { String(format: "%.1f%%", Double(v) / s * 100) }
        return "bbox x\(minX)..\(maxX) y\(minY)..\(maxY) (\(maxX - minX + 1)x\(maxY - minY + 1))"
            + "  L \(l) (\(pct(l)))  R \(r) (\(pct(r)))  T \(t) (\(pct(t)))  B \(b) (\(pct(b)))"
    }
}

/// Bounding box of the white glyph: any pixel whose red channel is high (background is blue).
func measure(_ img: CGImage) -> Margins {
    let w = img.width, h = img.height
    var buf = [UInt8](repeating: 0, count: w * h * 4)
    buf.withUnsafeMutableBytes { raw in
        let ctx = CGContext(data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8,
                            bytesPerRow: w * 4, space: srgb,
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(img, in: CGRect(x: 0, y: 0, width: w, height: h))
    }
    var minX = w, minY = h, maxX = 0, maxY = 0
    for y in 0..<h {
        for x in 0..<w where buf[(y * w + x) * 4] > 128 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }
    }
    return Margins(minX: minX, minY: minY, maxX: maxX, maxY: maxY, size: w)
}

// MARK: - Main

let icon = renderIcon(glyph)
print("make-icon: \(measure(icon))")
writePNG(icon, to: output)
