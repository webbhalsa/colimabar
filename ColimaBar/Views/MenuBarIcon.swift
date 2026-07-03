import AppKit

enum MenuBarIcon {
    static func build(cargoColor: NSColor, showUpdateBadge: Bool = false) -> NSImage {
        guard let body = NSImage(named: "Llama"),
              let outline = NSImage(named: "LlamaOutline") else {
            return NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "ColimaBar") ?? NSImage()
        }

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let outlineColor: NSColor = isDark ? .white : .black

        let size = body.size
        let fillLayer = maskedFill(cargoColor, using: body, size: size)
        let outlineLayer = maskedFill(outlineColor, using: outline, size: size)

        let result = NSImage(size: size, flipped: false) { rect in
            fillLayer.draw(in: rect)
            outlineLayer.draw(in: rect)
            if showUpdateBadge {
                drawUpdateBadge(in: rect)
            }
            return true
        }
        result.isTemplate = false
        return result
    }

    // Paint `color` into `size`, then keep only the pixels where `mask` is
    // opaque via destinationIn. Result is a solid-colored version of the mask
    // shape with a clean alpha channel.
    private static func maskedFill(_ color: NSColor, using mask: NSImage, size: NSSize) -> NSImage {
        NSImage(size: size, flipped: false) { rect in
            color.set()
            rect.fill()
            mask.draw(in: rect, from: .zero, operation: .destinationIn, fraction: 1.0)
            return true
        }
    }

    private static func drawUpdateBadge(in canvas: NSRect) {
        let d = min(canvas.width, canvas.height) * 0.32
        let x = canvas.maxX - d
        let y = canvas.maxY - d
        let dot = NSRect(x: x, y: y, width: d, height: d)
        NSColor(calibratedWhite: 1, alpha: 0.9).set()
        NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
        NSColor.systemRed.set()
        NSBezierPath(ovalIn: dot).fill()
    }
}
