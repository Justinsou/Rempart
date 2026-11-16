import AppKit

// Usage: swift make-icon.swift <sortie.iconset>
let out = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: out, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let rect = NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88)
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.2, yRadius: s * 0.2)
    NSGradient(starting: NSColor(red: 0.30, green: 0.55, blue: 0.48, alpha: 1),
               ending: NSColor(red: 0.25, green: 0.38, blue: 0.62, alpha: 1))!.draw(in: path, angle: -45)
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.5, weight: .semibold)
    if let sym = NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let tinted = NSImage(size: sym.size)
        tinted.lockFocus()
        sym.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
        NSColor.white.set()
        NSRect(origin: .zero, size: sym.size).fill(using: .sourceIn)
        tinted.unlockFocus()
        let r = NSRect(x: (s - tinted.size.width) / 2, y: (s - tinted.size.height) / 2,
                       width: tinted.size.width, height: tinted.size.height)
        tinted.draw(in: r)
    }
    img.unlockFocus()
    let rep = NSBitmapImageRep(data: img.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

for base in [16, 32, 128, 256, 512] {
    try! render(base).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base).png"))
    try! render(base * 2).write(to: URL(fileURLWithPath: "\(out)/icon_\(base)x\(base)@2x.png"))
}
