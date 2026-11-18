import AppKit
import SwiftUI

enum MenuBarIcon {
    /// Petite créature bleue pour la barre des menus.
    static let blob: NSImage = render(size: 18)

    private static func render(size: CGFloat) -> NSImage {
        let view = NSHostingView(rootView:
            BlobView(mood: .calm, size: size, glow: false, float: false)
                .frame(width: size, height: size)
        )
        view.frame = NSRect(x: 0, y: 0, width: size, height: size)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else {
            return NSImage(systemSymbolName: "shield.lefthalf.filled", accessibilityDescription: "Rempart")!
        }
        view.cacheDisplay(in: view.bounds, to: rep)
        let img = NSImage(size: NSSize(width: size, height: size))
        img.addRepresentation(rep)
        img.isTemplate = false
        return img
    }
}
