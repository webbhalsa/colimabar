import AppKit

enum MenuBarIcon {
    static func build(cargoColor: NSColor, showUpdateBadge: Bool = false) -> NSImage {
        guard let body = NSImage(named: "Llama"),
              let cargo = NSImage(named: "LlamaCargo") else {
            return NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: "ColimaBar") ?? NSImage()
        }

        let isDark = NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let bodyColor: NSColor = isDark ? .white : .black

        let tintedBody = tint(body, with: bodyColor)
        let tintedCargo = tint(cargo, with: cargoColor)

        let size = body.size
        let rect = NSRect(origin: .zero, size: size)
        let result = NSImage(size: size)
        result.lockFocus()
        tintedBody.draw(in: rect)
        tintedCargo.draw(in: rect)
        if showUpdateBadge {
            drawUpdateBadge(in: rect)
        }
        result.unlockFocus()
        result.isTemplate = false
        return result
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

    private static func tint(_ image: NSImage, with color: NSColor) -> NSImage {
        let size = image.size
        let out = NSImage(size: size)
        out.lockFocus()
        let rect = NSRect(origin: .zero, size: size)
        image.draw(in: rect)
        color.set()
        rect.fill(using: .sourceAtop)
        out.unlockFocus()
        return out
    }
}
