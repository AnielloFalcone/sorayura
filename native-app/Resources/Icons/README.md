# Sorayura icon assets

- `SorayuraMenuTemplate.png`: monochrome transparent S ribbon, loaded as an 18-point AppKit template image. macOS supplies its appearance for light/dark menu bars and selection.
- `SorayuraAppConcept.png`: original glass S concept, retained as a historical design reference.
- `Sorayura.icns`: macOS icon set derived from that source at all standard sizes (16–1024 pixels).

Generated with the built-in image generation tool. Menu-mark prompt: preserve the S ribbon silhouette and sweep direction from the selected Sorayura icon, including the upper-right and lower-left curls; remove the rounded-square tile, color, glow, shading and texture; produce one centered solid black flat silhouette with a fully transparent background; simplify fine folds for legibility at 18×18 pixels; no border, gray, shadow, text or particles.

The app-concept brief: a midnight glass macOS rounded square with a single sculptural translucent ribbon curling into an open S like a flowing aurora, ice blue with violet edge, soft refraction, bold silhouette and generous breathing room; no text, charts, particles or generic sparkle.

`SorayuraAppAuroraFlat.png` is the user-selected full-bleed opaque app-icon source: cyan, blue and lavender aurora bands forming an S on navy. The supplied 1254×1254 PNG is preserved unchanged; the asset catalog contains resized renditions through 1024 pixels. There is no pre-rendered rounded tile, transparent outer margin, border, drop shadow or glass reflection. macOS supplies the outer treatment. Design brief: preserve the flowing S and its upper-right/lower-left curls, use adjoining flat aurora color bands with subtle gradients on a full-square navy background, omit sculptural lighting, bevels, shadows, framing and text.

`SorayuraAppFlat.png` is the earlier single-color flat proposal, retained as a design reference. It is not assigned as the app icon.

The current app build compiles `Resources/Assets.xcassets/SorayuraAuroraIcon.appiconset` with Xcode's asset compiler. The compiler's icon metadata is merged into Info.plist; both Assets.car and the generated ICNS are bundled. `Sorayura.icns` in this folder is retained as the earlier reference export. Development and release staging directories use `.noindex` to avoid Spotlight registrations of temporary bundles. See [ICON-REVIEW.md](ICON-REVIEW.md) for the current Apple guidance review and its limits.
