# Aurora S icon review

Reviewed 9 October 2026 against Apple's current [App icons HIG](https://developer.apple.com/design/human-interface-guidelines/app-icons), [WWDC26 Icon Composer group lab](https://developer.apple.com/videos/play/wwdc2026/8012/) and [Icon Composer introduction](https://developer.apple.com/videos/play/wwdc2025/361/).

## Static artwork assessment

- **Composition:** one recognizable S, simple navy background, no text or decorative frame. Cyan/lavender bands support the aurora identity; recognizing the app does not depend on distinguishing those colors.
- **Canvas:** supplied PNG is square, 1254×1254, opaque RGB. Production renditions are generated at the standard macOS sizes through 1024×1024. No rounded mask is baked into the source.
- **Spacing:** approximate bright-symbol bounds are x=26–75%, y=16–84% of the source. The symbol is centered with room around the tips. These measurements describe the artwork; they are not an Apple-mandated numerical safe area.
- **Small sizes:** visually inspected actual 16-, 32- and 128-pixel renditions. The S remains identifiable; color-band separation and pointed curls become less distinct at 16 pixels. The menu bar uses a separate monochrome template optimized for its role.
- **Surface:** no baked glass reflections, bevel, border or drop shadow. Subtle color gradients and adjoining ribbon shapes are an artistic choice, not a claim that Apple requires flat icons. Apple's 2026 lab explicitly permits flat foreground treatments and still supports bitmap artwork.

## Verdict and limits

Suitable as the selected **static raster app icon**, using the compiled asset catalog and ICNS fallback. This is a design/packaging review, not Apple certification or an App Store review outcome.

Full adaptive Liquid Glass adoption remains separate work: reconstruct/export editable layers, prepare an Icon Composer `.icon` document, and inspect light/dark, clear and tinted treatments at multiple sizes and against different backgrounds. Apple recommends scalable vector layers and testing the actual system presentations. The current PNG/catalog does not provide independent layers or certify those appearances. Keeping the selected flat branding does not require adding simulated 3D lighting to the source.
