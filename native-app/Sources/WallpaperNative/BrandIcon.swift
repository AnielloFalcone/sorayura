import AppKit

@MainActor enum BrandIcon {
    static func menuImage() -> NSImage? {
        let url = Bundle.main.resourceURL?.appending(path: "Icons/SorayuraMenuTemplate.png")
        let image = url.flatMap { NSImage(contentsOf: $0) }
            ?? NSImage(systemSymbolName: "s.circle", accessibilityDescription: "Sorayura")
        image?.size = NSSize(width: 18, height: 18)
        image?.isTemplate = true
        image?.accessibilityDescription = "Sorayura"
        return image
    }
}
