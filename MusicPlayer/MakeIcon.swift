// 生成应用图标：swift MakeIcon.swift <输出目录>
import AppKit

let outDir = CommandLine.arguments[1]

func icon(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                               colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px)
    let rect = NSRect(x: 0, y: 0, width: s, height: s)
    NSGradient(starting: NSColor(red: 1.0, green: 0.22, blue: 0.37, alpha: 1),
               ending: NSColor(red: 0.35, green: 0.16, blue: 0.55, alpha: 1))!.draw(in: rect, angle: -60)
    let attr: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: s * 0.62),
        .foregroundColor: NSColor.white,
    ]
    let note = "♫" as NSString
    let sz = note.size(withAttributes: attr)
    note.draw(at: NSPoint(x: (s - sz.width) / 2, y: (s - sz.height) / 2), withAttributes: attr)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("Icon-76.png", 76), ("Icon-76@2x.png", 152)] {
    try icon(px).write(to: URL(fileURLWithPath: outDir).appendingPathComponent(name))
}
