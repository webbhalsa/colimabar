import AppKit

enum MenuBarIcon {
    static func build(cargoColor: NSColor) -> NSImage {
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
        result.unlockFocus()
        result.isTemplate = false
        return result
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
