// Renders the app icon: a slide on a projection screen with a folded "PDF" corner and a play
// badge. Usage: swift Tools/make_icon.swift Presently/Assets.xcassets/AppIcon.appiconset
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? ".")
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [CGFloat(hex >> 16 & 0xFF) / 255, CGFloat(hex >> 8 & 0xFF) / 255,
                                            CGFloat(hex & 0xFF) / 255, a])!
}

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [])
}

/// Draws in a 1024 × 1024 design space (y up), scaled to `pixels`.
func render(pixels: Int) -> Data {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)

    // macOS icon grid: 824 pt body, centered, with a soft drop shadow.
    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: rgb(0x000000, 0.35))
    ctx.addPath(bodyPath); ctx.setFillColor(rgb(0x1E2A5A)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(bodyPath); ctx.clip()
    linear(ctx, [rgb(0x3B5BDB), rgb(0x1B2559)], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
    // Projector light cone from the top.
    ctx.move(to: CGPoint(x: 470, y: 924)); ctx.addLine(to: CGPoint(x: 554, y: 924))
    ctx.addLine(to: CGPoint(x: 860, y: 420)); ctx.addLine(to: CGPoint(x: 164, y: 420)); ctx.closePath()
    ctx.clip()
    linear(ctx, [rgb(0xFFFFFF, 0.22), rgb(0xFFFFFF, 0.0)], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 420))
    ctx.restoreGState()

    // Stand of the projection screen.
    ctx.setStrokeColor(rgb(0xC9D3F5)); ctx.setLineWidth(22); ctx.setLineCap(.round)
    ctx.move(to: CGPoint(x: 512, y: 330)); ctx.addLine(to: CGPoint(x: 512, y: 190)); ctx.strokePath()
    ctx.move(to: CGPoint(x: 512, y: 300)); ctx.addLine(to: CGPoint(x: 400, y: 175)); ctx.strokePath()
    ctx.move(to: CGPoint(x: 512, y: 300)); ctx.addLine(to: CGPoint(x: 624, y: 175)); ctx.strokePath()

    // Slide (16:10) with folded top-right corner.
    let slide = CGRect(x: 196, y: 318, width: 632, height: 420)
    let fold: CGFloat = 120, r: CGFloat = 26
    let sheet = CGMutablePath()
    sheet.move(to: CGPoint(x: slide.minX + r, y: slide.minY))
    sheet.addLine(to: CGPoint(x: slide.maxX - r, y: slide.minY))
    sheet.addQuadCurve(to: CGPoint(x: slide.maxX, y: slide.minY + r), control: CGPoint(x: slide.maxX, y: slide.minY))
    sheet.addLine(to: CGPoint(x: slide.maxX, y: slide.maxY - fold))
    sheet.addLine(to: CGPoint(x: slide.maxX - fold, y: slide.maxY))
    sheet.addLine(to: CGPoint(x: slide.minX + r, y: slide.maxY))
    sheet.addQuadCurve(to: CGPoint(x: slide.minX, y: slide.maxY - r), control: CGPoint(x: slide.minX, y: slide.maxY))
    sheet.addLine(to: CGPoint(x: slide.minX, y: slide.minY + r))
    sheet.addQuadCurve(to: CGPoint(x: slide.minX + r, y: slide.minY), control: CGPoint(x: slide.minX, y: slide.minY))
    sheet.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0x000000, 0.4))
    ctx.addPath(sheet); ctx.setFillColor(rgb(0xFFFFFF)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(sheet); ctx.clip()
    linear(ctx, [rgb(0xFFFFFF), rgb(0xE8ECF8)], from: CGPoint(x: 512, y: slide.maxY), to: CGPoint(x: 512, y: slide.minY))
    ctx.restoreGState()

    // Folded corner in PDF red.
    let flap = CGMutablePath()
    flap.move(to: CGPoint(x: slide.maxX - fold, y: slide.maxY))
    flap.addLine(to: CGPoint(x: slide.maxX - fold + 14, y: slide.maxY - fold + 14))
    flap.addQuadCurve(to: CGPoint(x: slide.maxX, y: slide.maxY - fold),
                      control: CGPoint(x: slide.maxX - fold + 4, y: slide.maxY - fold - 4))
    flap.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: -6, height: -6), blur: 12, color: rgb(0x000000, 0.25))
    ctx.addPath(flap); ctx.setFillColor(rgb(0xE5383B)); ctx.fillPath()
    ctx.restoreGState()

    // Slide content: title bar and a small bar chart.
    func bar(_ rect: CGRect, _ color: CGColor) {
        ctx.addPath(CGPath(roundedRect: rect, cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.setFillColor(color); ctx.fillPath()
    }
    bar(CGRect(x: 250, y: 640, width: 330, height: 40), rgb(0x1B2559))
    bar(CGRect(x: 250, y: 595, width: 220, height: 22), rgb(0x9AA6CF))
    let bars: [(CGFloat, UInt32)] = [(90, 0x3B5BDB), (150, 0x4C6EF5), (115, 0x748FFC), (190, 0xF59F00)]
    for (i, (h, c)) in bars.enumerated() {
        bar(CGRect(x: 262 + CGFloat(i) * 78, y: 372, width: 52, height: h), rgb(c))
    }

    // Play badge.
    let badge = CGRect(x: 620, y: 240, width: 250, height: 250)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 20, color: rgb(0x000000, 0.4))
    ctx.addEllipse(in: badge); ctx.setFillColor(rgb(0xF76707)); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: badge); ctx.clip()
    linear(ctx, [rgb(0xFF922B), rgb(0xE8590C)], from: CGPoint(x: badge.midX, y: badge.maxY), to: CGPoint(x: badge.midX, y: badge.minY))
    ctx.restoreGState()
    ctx.addEllipse(in: badge.insetBy(dx: 6, dy: 6)); ctx.setStrokeColor(rgb(0xFFFFFF, 0.9)); ctx.setLineWidth(10); ctx.strokePath()
    let c = CGPoint(x: badge.midX + 12, y: badge.midY)
    ctx.move(to: CGPoint(x: c.x - 42, y: c.y + 62)); ctx.addLine(to: CGPoint(x: c.x + 62, y: c.y))
    ctx.addLine(to: CGPoint(x: c.x - 42, y: c.y - 62)); ctx.closePath()
    ctx.setFillColor(rgb(0xFFFFFF)); ctx.setLineJoin(.round); ctx.setLineWidth(18); ctx.setStrokeColor(rgb(0xFFFFFF))
    ctx.drawPath(using: .fillStroke)

    let image = ctx.makeImage()!
    return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!
}

var entries: [String] = []
for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let name = "icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png"
        try! render(pixels: points * scale).write(to: outDir.appendingPathComponent(name))
        entries.append("""
            {
              "filename" : "\(name)",
              "idiom" : "mac",
              "scale" : "\(scale)x",
              "size" : "\(points)x\(points)"
            }
        """)
    }
}
let json = "{\n  \"images\" : [\n\(entries.joined(separator: ",\n"))\n  ],\n  \"info\" : {\n    \"author\" : \"xcode\",\n    \"version\" : 1\n  }\n}\n"
try! json.write(to: outDir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
