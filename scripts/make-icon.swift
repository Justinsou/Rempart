import AppKit

// Usage: swift make-icon.swift <sortie.iconset>
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func blobPath(center c: CGPoint, radius r: CGFloat) -> NSBezierPath {
    let p = NSBezierPath()
    for i in 0...240 {
        let t = Double(i) / 240 * 2 * .pi
        let rad = r * (0.95 + 0.05 * CGFloat(cos(8 * t)))
        let pt = CGPoint(x: c.x + rad * CGFloat(cos(t)), y: c.y + rad * CGFloat(sin(t)))
        if i == 0 { p.move(to: pt) } else { p.line(to: pt) }
    }
    p.close()
    return p
}

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let rect = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let bg = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    NSColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1).setFill()
    bg.fill()

    let c = CGPoint(x: s / 2, y: s / 2)
    let blob = blobPath(center: c, radius: s * 0.32)
    NSGradient(colors: [NSColor(red: 0.04, green: 0.57, blue: 0.86, alpha: 1),
                        NSColor(red: 0.42, green: 0.78, blue: 0.96, alpha: 1)])!
        .draw(in: blob, relativeCenterPosition: .zero)

    let ink = NSColor(red: 0.10, green: 0.20, blue: 0.40, alpha: 1)
    ink.setFill()
    for dx in [-0.13, 0.13] {
        NSBezierPath(ovalIn: NSRect(x: c.x + s * dx - s * 0.03, y: c.y + s * 0.02, width: s * 0.06, height: s * 0.06)).fill()
    }
    let smile = NSBezierPath()
    smile.move(to: CGPoint(x: c.x - s * 0.06, y: c.y - s * 0.07))
    smile.curve(to: CGPoint(x: c.x + s * 0.06, y: c.y - s * 0.07),
                controlPoint1: CGPoint(x: c.x - s * 0.03, y: c.y - s * 0.12),
                controlPoint2: CGPoint(x: c.x + s * 0.03, y: c.y - s * 0.12))
    smile.lineWidth = s * 0.022
    smile.lineCapStyle = .round
    ink.setStroke()
    smile.stroke()
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
