// store-assets.swift - App Store creative assets (iOS 27+): the product page
// header (21:9, 3840 x 1646) and the search results asset (3:2, 3840 x 2560),
// in every language, opaque PNG.
//
// Usage, from the repository root, after design/screenshots.sh:
//   swift design/store-assets.swift
// Reads appstore/screenshots/iphone-6.3/<lang>/ and writes
// appstore/creative/<lang>/header.png and search.png (git-ignored).
//
// Content follows Apple's asset guidance: one idea, the real app on screen,
// short localized text, no prices, URLs, copyright symbols or other brands.
// All geometry is on the asset's own pixel canvas with y pointing DOWN.

import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let srgb = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: srgb, components: [CGFloat((hex >> 16) & 0xFF) / 255, CGFloat((hex >> 8) & 0xFF) / 255,
                                           CGFloat(hex & 0xFF) / 255, a])!
}

let blueTop = rgb(0x0A93E4)      // same gradient as the app icon
let blueBottom = rgb(0x005DAA)
let white = rgb(0xFFFFFF)

// Headline and subline per language. Kept short: Apple asks for text that
// adds to the image, legible at a glance.
struct Copy { let header: String; let headerSub: String; let search: String; let searchSub: String }
let COPY: [String: Copy] = [
    "en": Copy(header: "Press Scan on the printer.\nThe PDF lands on your phone.",
               headerSub: "Over Wi-Fi. No cables, no cloud, no account.",
               search: "Scan from your printer to your phone",
               searchSub: "PDF or JPEG over Wi-Fi. No cables, no cloud."),
    "fr": Copy(header: "Appuyez sur Num\u{E9}riser.\nLe PDF arrive sur votre t\u{E9}l\u{E9}phone.",
               headerSub: "Par Wi-Fi. Sans c\u{E2}ble, sans cloud, sans compte.",
               search: "Num\u{E9}risez de l\u{2019}imprimante vers votre t\u{E9}l\u{E9}phone",
               searchSub: "PDF ou JPEG par Wi-Fi. Sans c\u{E2}ble, sans cloud."),
    "es": Copy(header: "Pulsa Escanear en la impresora.\nEl PDF llega a tu tel\u{E9}fono.",
               headerSub: "Por Wi-Fi. Sin cables, sin nube, sin cuenta.",
               search: "Escanea de la impresora a tu tel\u{E9}fono",
               searchSub: "PDF o JPEG por Wi-Fi. Sin cables, sin nube."),
    "zh-Hans": Copy(header: "\u{5728}\u{6253}\u{5370}\u{673A}\u{4E0A}\u{6309}\u{4E0B}\u{626B}\u{63CF}\u{FF0C}\nPDF \u{76F4}\u{8FBE}\u{4F60}\u{7684}\u{624B}\u{673A}\u{3002}",
                    headerSub: "\u{901A}\u{8FC7} Wi-Fi \u{4F20}\u{8F93}\u{FF0C}\u{65E0}\u{9700}\u{6570}\u{636E}\u{7EBF}\u{3001}\u{4E91}\u{7AEF}\u{6216}\u{8D26}\u{6237}\u{3002}",
                    search: "\u{4ECE}\u{6253}\u{5370}\u{673A}\u{626B}\u{63CF}\u{5230}\u{4F60}\u{7684}\u{624B}\u{673A}",
                    searchSub: "\u{901A}\u{8FC7} Wi-Fi \u{83B7}\u{53D6} PDF \u{6216} JPEG\u{FF0C}\u{65E0}\u{9700}\u{6570}\u{636E}\u{7EBF}\u{6216}\u{4E91}\u{7AEF}\u{3002}"),
]

// MARK: - Drawing helpers (y down)

func canvas(_ w: Int, _ h: Int) -> CGContext {
    let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: srgb,
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(h))
    ctx.scaleBy(x: 1, y: -1)
    let grad = CGGradient(colorsSpace: srgb, colors: [blueTop, blueBottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: .zero, end: CGPoint(x: w, y: h), options: [])
    return ctx
}

func load(_ url: URL) -> CGImage {
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fatalError("store-assets: cannot read \(url.path); run design/screenshots.sh first")
    }
    return img
}

/// Draws an image upright into a y-down rect.
func drawImage(_ ctx: CGContext, _ img: CGImage, _ r: CGRect) {
    ctx.saveGState()
    ctx.translateBy(x: r.minX, y: r.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.interpolationQuality = .high
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
    ctx.restoreGState()
}

/// A phone: dark bezel, rounded screen showing a real screenshot, soft shadow.
func phone(_ ctx: CGContext, _ shot: CGImage, height h: CGFloat, center c: CGPoint) {
    let w = h * CGFloat(shot.width) / CGFloat(shot.height)
    let bezel = w * 0.035
    let outer = CGRect(x: c.x - w / 2 - bezel, y: c.y - h / 2 - bezel, width: w + 2 * bezel, height: h + 2 * bezel)
    let outerPath = CGPath(roundedRect: outer, cornerWidth: outer.width * 0.15, cornerHeight: outer.width * 0.15, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: h * 0.02), blur: h * 0.05, color: rgb(0x001A33, 0.45))
    ctx.addPath(outerPath)
    ctx.setFillColor(rgb(0x10161D))
    ctx.fillPath()
    ctx.restoreGState()
    let screen = CGRect(x: c.x - w / 2, y: c.y - h / 2, width: w, height: h)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: screen, cornerWidth: w * 0.13, cornerHeight: w * 0.13, transform: nil))
    ctx.clip()
    drawImage(ctx, shot, screen)
    ctx.restoreGState()
}

/// A generic all-in-one printer in white line art, a page coming out of it.
func printer(_ ctx: CGContext, center c: CGPoint, width w: CGFloat) {
    let s = w / 100   // drawn on a 100-unit grid
    func r(_ x: CGFloat, _ y: CGFloat, _ ww: CGFloat, _ hh: CGFloat) -> CGRect {
        CGRect(x: c.x + (x - 50) * s, y: c.y + (y - 40) * s, width: ww * s, height: hh * s)
    }
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 2 * s), blur: 6 * s, color: rgb(0x001A33, 0.35))
    ctx.setFillColor(white)
    // Scanner lid and body.
    ctx.addPath(CGPath(roundedRect: r(8, 10, 84, 14), cornerWidth: 4 * s, cornerHeight: 4 * s, transform: nil))
    ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: r(4, 27, 92, 38), cornerWidth: 7 * s, cornerHeight: 7 * s, transform: nil))
    ctx.fillPath()
    ctx.restoreGState()
    // Control panel and output slot, in the blue.
    ctx.setFillColor(rgb(0x0A7AC9))
    ctx.addPath(CGPath(roundedRect: r(14, 34, 24, 9), cornerWidth: 2 * s, cornerHeight: 2 * s, transform: nil))
    ctx.fillPath()
    ctx.setFillColor(rgb(0x2EC27E))
    ctx.fillEllipse(in: r(80, 35, 6, 6))
    ctx.setFillColor(rgb(0x0B5FA5))
    ctx.fill(r(24, 54, 52, 4))
    // The page coming out, with text lines.
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: 1.5 * s), blur: 4 * s, color: rgb(0x001A33, 0.3))
    ctx.setFillColor(rgb(0xF4F8FC))
    ctx.fill(r(29, 56, 42, 30))
    ctx.restoreGState()
    ctx.setFillColor(rgb(0x9FB4C8))
    for (i, len) in [30.0, 30.0, 24.0, 30.0].enumerated() {
        ctx.fill(r(35, 62 + CGFloat(i) * 5.5, CGFloat(len), 2))
    }
}

/// Dotted arc ending in a solid arrowhead at b, bulging upwards by `lift`.
func arrow(_ ctx: CGContext, from a: CGPoint, to b: CGPoint, lift: CGFloat, width lw: CGFloat) {
    let ctrl = CGPoint(x: (a.x + b.x) / 2, y: min(a.y, b.y) - lift)
    let dx = b.x - ctrl.x, dy = b.y - ctrl.y, len = (dx * dx + dy * dy).squareRoot()
    let ux = dx / len, uy = dy / len, head = lw * 3.2
    // The dots stop where the head starts, so the two never overlap.
    let neck = CGPoint(x: b.x - ux * head, y: b.y - uy * head)
    ctx.saveGState()
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.85))
    ctx.setLineWidth(lw)
    ctx.setLineCap(.round)
    ctx.setLineDash(phase: 0, lengths: [lw * 0.1, lw * 2.4])
    ctx.move(to: a)
    ctx.addQuadCurve(to: neck, control: ctrl)
    ctx.strokePath()
    ctx.setFillColor(rgb(0xFFFFFF, 0.95))
    ctx.move(to: b)
    ctx.addLine(to: CGPoint(x: neck.x - uy * head * 0.75, y: neck.y + ux * head * 0.75))
    ctx.addLine(to: CGPoint(x: neck.x + uy * head * 0.75, y: neck.y - ux * head * 0.75))
    ctx.closePath()
    ctx.fillPath()
    ctx.restoreGState()
}

/// Wrapped text in a rect (y down). Returns the height actually used.
@discardableResult
func text(_ ctx: CGContext, _ s: String, in rect: CGRect, size: CGFloat, bold: Bool, alpha: CGFloat = 1,
          align: CTTextAlignment = .left) -> CGFloat {
    let base = CTFontCreateUIFontForLanguage(bold ? .emphasizedSystem : .system, size, nil)!
    let font = bold ? (CTFontCreateCopyWithSymbolicTraits(base, size, nil, .traitBold, .traitBold) ?? base) : base
    var alignment = align
    var spacing: CGFloat = size * 0.12
    // The setting values must stay valid while the style is created.
    let para = withUnsafeBytes(of: &alignment) { al in
        withUnsafeBytes(of: &spacing) { sp in
            let settings = [CTParagraphStyleSetting(spec: .alignment, valueSize: al.count, value: al.baseAddress!),
                            CTParagraphStyleSetting(spec: .lineSpacingAdjustment, valueSize: sp.count, value: sp.baseAddress!)]
            return CTParagraphStyleCreate(settings, settings.count)
        }
    }
    let attrs: [CFString: Any] = [kCTFontAttributeName: font, kCTForegroundColorAttributeName: rgb(0xFFFFFF, alpha),
                                  kCTParagraphStyleAttributeName: para]
    let str = CFAttributedStringCreate(nil, s as CFString, attrs as CFDictionary)!
    let setter = CTFramesetterCreateWithAttributedString(str)
    let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
                                                           CGSize(width: rect.width, height: .greatestFiniteMagnitude), nil)
    // CoreText draws y-up: flip locally around the text block.
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.minY + fit.height)
    ctx.scaleBy(x: 1, y: -1)
    let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0),
                                         CGPath(rect: CGRect(x: 0, y: 0, width: rect.width, height: fit.height + 2), transform: nil), nil)
    CTFrameDraw(frame, ctx)
    ctx.restoreGState()
    return fit.height
}

func write(_ ctx: CGContext, _ url: URL) {
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, ctx.makeImage()!, nil)
    if !CGImageDestinationFinalize(dest) { fatalError("store-assets: cannot write \(url.path)") }
    print("store-assets: wrote \(url.path)")
}

// MARK: - Layouts

/// Header, 21:9: headline on the left, printer -> phone on the right, all
/// inside the central 90% so a moderate crop keeps every element.
func header(_ lang: String, _ c: Copy, listening: CGImage) -> CGContext {
    let ctx = canvas(3840, 1646)
    let used = text(ctx, c.header, in: CGRect(x: 360, y: 470, width: 1640, height: 700), size: 120, bold: true)
    text(ctx, c.headerSub, in: CGRect(x: 360, y: 470 + used + 60, width: 1640, height: 300), size: 64, bold: false, alpha: 0.85)
    printer(ctx, center: CGPoint(x: 2370, y: 900), width: 600)
    arrow(ctx, from: CGPoint(x: 2540, y: 650), to: CGPoint(x: 2800, y: 600), lift: 230, width: 22)
    phone(ctx, listening, height: 1300, center: CGPoint(x: 3160, y: 823))
    return ctx
}

/// Search results, 3:2: what the app does in one line on top, then the real
/// app: printer -> listening screen, and the scan it produced.
func search(_ lang: String, _ c: Copy, listening: CGImage, preview: CGImage) -> CGContext {
    let ctx = canvas(3840, 2560)
    let used = text(ctx, c.search, in: CGRect(x: 360, y: 210, width: 3120, height: 500), size: 160, bold: true, align: .center)
    text(ctx, c.searchSub, in: CGRect(x: 460, y: 210 + used + 50, width: 2920, height: 200), size: 80, bold: false,
         alpha: 0.85, align: .center)
    printer(ctx, center: CGPoint(x: 840, y: 1680), width: 760)
    arrow(ctx, from: CGPoint(x: 1120, y: 1330), to: CGPoint(x: 1480, y: 1250), lift: 260, width: 26)
    phone(ctx, listening, height: 1600, center: CGPoint(x: 1970, y: 1700))
    phone(ctx, preview, height: 1600, center: CGPoint(x: 2990, y: 1700))
    return ctx
}

// MARK: - Main

for lang in ["en", "fr", "es", "zh-Hans"] {
    guard let c = COPY[lang] else { continue }
    let shots = repo.appendingPathComponent("appstore/screenshots/iphone-6.3/\(lang)")
    let listening = load(shots.appendingPathComponent("01-listening.png"))
    let preview = load(shots.appendingPathComponent("02-scan-preview.png"))
    let out = repo.appendingPathComponent("appstore/creative/\(lang)")
    write(header(lang, c, listening: listening), out.appendingPathComponent("header.png"))
    write(search(lang, c, listening: listening, preview: preview), out.appendingPathComponent("search.png"))
}
