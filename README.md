# Sorayura

A native macOS app built with Swift, AppKit, SwiftUI and Metal. System widgets and animations live on your desktop, controlled from the menu bar with no Dock icon. M2 is in development.

## Why Sorayura?

**Sorayura** is a coined name inspired by Japanese: *sora* (空) means “sky”, while *yura* echoes *yurayura* (ゆらゆら), a gentle swaying motion.

The name evokes a **sky in motion**: a changing space filled with light and shapes. That is the idea behind the app: turning the desktop into a living environment where animations and widgets make your Mac’s activity visible.

## Getting started

Open **native-app/build/Sorayura.app**. In the menu bar, choose the settings item (“Widget e sfondo…”) or edit layout (“Modifica layout…”). The app’s current interface is in Italian.

Building requires Xcode Command Line Tools and macOS 14 or later:

```sh
cd native-app
./build-native.sh
```

The repository contains the native Swift app and does not require Node, Rust or Tauri.

## M1 features

- Widgets: clock, CPU, memory, network, battery, disk, uptime and Mac name.
- CPU and memory bars or charts covering the last 90 seconds; compact and expanded views.
- Expanded memory details: cache, swap, app memory, wired memory and compressed memory. Values are estimates from macOS counters, rather than an exact reproduction of Activity Monitor.
- Secondary click (two fingers when configured on the trackpad) opens a widget’s menu. Hold a click for 550 ms and drag to move it.
- Grid or free placement in edit mode, adjustable cell sizes and widget dimensions up to the available columns and rows; an Add menu for hidden items.
- Aurora, Pulse, Trails and Luminous Core animations, with configurable resources, colors, position and size.
- Warning and critical thresholds with configurable colors. Network rates in bps, Kbps, Mbps or Gbps.
- Independent content and positions per monitor; display identification and matching through stable macOS identities.
- Minimal, Glass, Monitoring and Cyber presets; custom presets and undo for the most recent application.
- Minimal, Glass and Cyber widget themes. Glass uses Liquid Glass on macOS 26+, with native materials on earlier versions.
- JSON import/export including the wallpaper image, validation and monitor matching.
- Optional launch at login through Service Management, available in General settings.
- Automatic saving and a recovery copy; handling of resolution changes, monitor changes and wake.

## Wallpaper and Spaces

When wallpaper synchronization is enabled (“Usa lo stesso sfondo anche in macOS”), the app also sets the static macOS wallpaper. Mission Control shows this image; widgets and animations are desktop windows.

On Space changes and wake, the app reapplies the wallpaper to the active Space. Unvisited Spaces may retain their previous wallpaper until opened. Use the reapply wallpaper action (“Riapplica sfondo”) in Displays settings if needed. The app does not set a video as the system wallpaper.

## Preferences and backups

Files are stored in `~/Library/Application Support/dev.aniello.macsystemwallpaper/`:

- `native-settings.json`: current configuration.
- `native-settings.backup.json`: the previous readable copy, used if the current file is damaged.
- `presets.json`: custom presets.
- `wallpapers/`: generated or imported wallpapers.

The first launch recovers settings from the former Tauri version when available. Numeric monitor identifiers are migrated while preserving content and positions.

Exports include the current configuration and up to 25 MB of wallpaper image data. Custom presets remain in their local collection. Import files may be up to 35 MB. Launch at login is a macOS preference and is not transferred through backups.

The app bundle and process are named **Sorayura**. The internal identifier and data folder retain the previous name to preserve preferences, layouts and permissions. Existing Claude connections using the supported previous paths are relocated on Sorayura’s first launch.

## Verification

After building, from `native-app/`:

```sh
'build/Sorayura.app/Contents/MacOS/Sorayura' --check-m1
```

This checks presets, JSON encoding, monitor matching, compatibility with previous settings and rejection of invalid configurations. Login, sleep/wake and physical gestures require a real session; see [performance and verification](native-app/PERFORMANCE.md).

Temperature in degrees is unavailable; the thermal widget shows the state reported by macOS.

## M2 integrations

Local Codex/Claude Code dashboards, optional Claude status line connections, a thermal widget and animation energy policies. Details and limitations: [M2](native-app/M2.md).

## Beta distribution

DMG preparation, checks, signing and notarization: [release procedure](native-app/release/README.md). Local 0.5.1 candidates are separate from the public Developer ID signed package. Verification status: [performance and verification](native-app/PERFORMANCE.md).

Homebrew support is being prepared in the [Sorayura tap](https://github.com/AnielloFalcone/homebrew-sorayura). The Cask will become installable after the first signed and notarized release. See the [Homebrew procedure](native-app/release/HOMEBREW.md).

Repository: [AnielloFalcone/sorayura](https://github.com/AnielloFalcone/sorayura).

## License

[MIT](LICENSE) — Copyright © 2026 Aniello Falcone.
