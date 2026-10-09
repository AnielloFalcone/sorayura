# Sorayura icon assets

- `SorayuraMenuTemplate.png`: monochrome transparent S ribbon, loaded as an 18-point AppKit template image. macOS supplies its appearance for light/dark menu bars and selection.
- `SorayuraAppConcept.png`: user-selected full-color S ribbon, the source for the app icon.
- `Sorayura.icns`: macOS icon set derived from that source at all standard sizes (16–1024 pixels).

Generated with the built-in image generation tool. Menu-mark prompt: preserve the S ribbon silhouette and sweep direction from the selected Sorayura icon, including the upper-right and lower-left curls; remove the rounded-square tile, color, glow, shading and texture; produce one centered solid black flat silhouette with a fully transparent background; simplify fine folds for legibility at 18×18 pixels; no border, gray, shadow, text or particles.

The app-concept brief: a midnight glass macOS rounded square with a single sculptural translucent ribbon curling into an open S like a flowing aurora, ice blue with violet edge, soft refraction, bold silhouette and generous breathing room; no text, charts, particles or generic sparkle.

The current app build compiles `Resources/Assets.xcassets/SorayuraAppIcon.appiconset` with Xcode's asset compiler. The compiler's icon metadata is merged into Info.plist; both Assets.car and the generated ICNS are bundled. `Sorayura.icns` in this folder is retained as the earlier reference export. Development and release staging directories use `.noindex` to avoid Spotlight registrations of temporary bundles.
