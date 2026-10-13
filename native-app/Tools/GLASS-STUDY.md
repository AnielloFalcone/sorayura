# Native Liquid Glass visual study

## Purpose

Isolate native material behavior from Sorayura's widgets and renderer. This study uses real SwiftUI `glassEffect` and AppKit `NSGlassEffectView`, with Regular/Clear variants and large cards/small native capsules. It does not add a custom rim, blur, refraction shader, tint or private API.

## Run

Requires macOS 26+ and full Xcode 26+. Run from the repository root:

```sh
mkdir -p native-app/build.noindex/glass-study
swiftc -parse-as-library native-app/Tools/GlassStudy.swift \
  -o native-app/build.noindex/glass-study/GlassStudy
native-app/build.noindex/glass-study/GlassStudy \
  native-app/build.noindex/glass-study
```

The study briefly focuses its own test windows, captures only its own window via `SCShareableContent.currentProcess` and `SCScreenshotManager`, closes its windows and reactivates the previously foreground application. It does not modify Sorayura preferences or require recording other applications. All labels/data are fixtures. Output is ignored by Git.

## Observed on 13 October 2026

Four matching captures, with the app active throughout:

| Background | Window | Output |
| --- | --- | --- |
| Colored shapes and gradient | Key | `rich-active.png` |
| Same colored shapes and gradient | Non-key | `rich-inactive.png` |
| Smooth gradient | Key | `uniform-active.png` |
| Same smooth gradient | Non-key | `uniform-inactive.png` |

- Key Clear surfaces show pronounced edge highlights and sharper lensing of underlying shapes. Both SwiftUI and AppKit produce these optical features with native APIs.
- Moving key status to a second test window softens the main window's glass and removes much of its bright rim, even while the app remains active. Changing framework does not remove that behavior.
- The smooth-gradient/non-key combination closely reproduces the flat panels in the user's desktop screenshot, including small capsules. This is direct evidence that window state and low-detail background contribute; it does not prove they are the only causes in the full app.
- Regular remains more diffused than Clear over rich content. Native controls/text render inside the AppKit material in both window states.
- The outputs do not establish exact Control Center parity, assess all card sizes or backgrounds, or measure GPU/energy. The native desktop windows remain non-key during ordinary use.

## Consequences for Sorayura

Keep the selected native implementation. Do not describe the active Clear appearance as guaranteed for a non-key desktop surface. Public `NSGlassEffectView` exposes style, tint, corner radius and interaction; no explicit always-active glass property was found in the reviewed SDK surface. This is not proof that every conceivable public approach is impossible. Focus manipulation during normal wallpaper use is not an appropriate way to preserve this appearance.

Native behavior can be verified with this study when the OS or SDK changes. A separate investigation would be required for edit-mode focus behavior or another window architecture; neither was changed by this study.

## Primary references

- [Meet Liquid Glass](https://developer.apple.com/videos/play/wwdc2025/219/): native variants, adaptivity, content/background and size effects.
- [Build an AppKit app with the new design](https://developer.apple.com/videos/play/wwdc2025/310/): content ownership and grouped glass sampling.
- [NSGlassEffectView](https://developer.apple.com/documentation/appkit/nsglasseffectview): public API surface.
- [Apple HIG: Color](https://developer.apple.com/design/human-interface-guidelines/color): surrounding content and large-surface legibility.

These sources describe native design/API intent. Window-state conclusions above come from the captured experiment, not from unanswered forum posts.
