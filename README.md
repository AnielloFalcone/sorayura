# Sorayura

A native macOS app built with Swift, AppKit, SwiftUI and Metal. System widgets and animations live on your desktop, controlled from the menu bar with no Dock icon. M2 is in development.

## Why Sorayura?

**Sorayura** is a coined name inspired by Japanese: *sora* (空) means “sky”, while *yura* echoes *yurayura* (ゆらゆら), a gentle swaying motion.

The name evokes a **sky in motion**: a changing space filled with light and shapes. That is the idea behind the app: turning the desktop into a living environment where animations and widgets make your Mac’s activity visible.

## Getting started

Download the Apple Silicon beta from [GitHub Releases](https://github.com/AnielloFalcone/sorayura/releases) and move Sorayura to Applications. The ADHOC beta is not notarized; see the first-launch instructions below. To build from source instead, use the commands below and open **native-app/build.noindex/Sorayura.app**. In the menu bar, choose “Settings…” or “Edit layout…” (Italian: “Impostazioni…” / “Modifica layout…”). The interface supports English, Italian and Spanish. In General → Language, follow the Mac’s preferred language or choose a language explicitly. System dialogs follow macOS.

Building requires full Xcode 26 or later (including the macOS SDK for Liquid Glass); Command Line Tools alone are insufficient. The app targets macOS 14 or later, with older-system material fallbacks. Builds have been verified with Xcode 27 on Apple Silicon:

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

On a fresh installation, Sorayura keeps the current macOS wallpaper on every display and overlays only widgets and animations. Choose a different style in Wallpaper settings to use a Sorayura background; macOS wallpaper synchronization starts disabled. Existing saved preferences are preserved.

When wallpaper synchronization is enabled (“Usa lo stesso sfondo anche in macOS”), the app also sets the static macOS wallpaper. Mission Control shows this image; widgets and animations are desktop windows.

Wallpaper synchronization runs when you change the selected background or a display configuration requires a new image. Layout edits, Space changes and wake recovery do not force wallpaper replacement. Unvisited Spaces may retain their previous wallpaper until opened. Use the reapply wallpaper action (“Riapplica sfondo”) in Displays settings if needed. The app does not set a video as the system wallpaper.

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
'build.noindex/Sorayura.app/Contents/MacOS/Sorayura' --check-m1
```

This checks presets, JSON encoding, monitor matching, compatibility with previous settings and rejection of invalid configurations. Login, sleep/wake and physical gestures require a real session; see [performance and verification](native-app/PERFORMANCE.md).

Temperature in degrees is unavailable; the thermal widget shows the state reported by macOS.

## M2 integrations

Local Codex/Claude Code dashboards, optional Claude status line connections, a thermal widget and animation energy policies. Details and limitations: [M2](native-app/M2.md).

## Beta distribution

DMG preparation, checks, signing and notarization: [release procedure](native-app/release/README.md). Public betas can use an explicitly labeled ad hoc signature without Apple notarization; local candidates remain separate. Verification status: [performance and verification](native-app/PERFORMANCE.md).

Homebrew support is being prepared in the [Sorayura tap](https://github.com/AnielloFalcone/homebrew-sorayura). The Cask will become installable after the first signed and notarized release. See the [Homebrew procedure](native-app/release/HOMEBREW.md).

Repository: [AnielloFalcone/sorayura](https://github.com/AnielloFalcone/sorayura).

## License

[MIT](LICENSE) — Copyright © 2026 Aniello Falcone.

### Download the beta

[GitHub Releases](https://github.com/AnielloFalcone/sorayura/releases) provides the Apple Silicon beta. Packages marked **SELF-SIGNED** or **ADHOC** are unnotarized. Move the app to Applications; if macOS blocks its first launch, approve Sorayura in System Settings → Privacy & Security → Open Anyway. See [Apple’s instructions](https://support.apple.com/en-ie/102445) and the release notes for compatibility and verification limits. Managed Macs may disallow this exception. Source builds remain available through the instructions above.

### In-app updates

Starting with build 35, General settings includes **Check for updates…**. Sparkle checks a signed feed hosted in this repository and installs a verified GitHub release after confirmation. Builds 33 and 34 need one manual upgrade. Checks and installs are user-initiated. Calendar and mixer app selections remain saved if macOS asks for fresh consent after a signing certificate change.

### Clipboard

Settings → Clipboard enables an opt-in, local history of text, links and images. Open its searchable
panel from the menu bar or ⌘⇧V (registered only when collection is enabled). Arrow
keys select and ⌘C copies with available RTF formatting. **Paste without formatting**
uses Accessibility permission to paste plain text into the app you opened the panel from.

Pause collection, exclude apps, pin up to 50 favorites and choose a recent-item
limit. Confidential/transient clipboard markers and major password-manager apps
are excluded, but unmarked secrets cannot be identified reliably. Copied images
and single local image files appear as thumbnails. History stays in a private local file, without
additional encryption or network transmission, and is not included in layout
exports. Disabling collection retains it; clear recent items or all data explicitly.
macOS may require clipboard-access consent. Scenes preserve these global settings.

### Scenes

Save the current desktop under Settings → Scenes and activate it from Sorayura's
menu bar. Existing personal presets remain available as scenes. Scenes can be
renamed, updated from the current desktop, removed, or linked to one app.

Optional automatic switching activates the linked scene when its app becomes
frontmost. It keeps that scene when you switch to an unrelated app, pauses during
layout editing, and is off by default. Each app belongs to at most one scene.
Scene changes and scene undo preserve global integration opt-ins, account setup,
warning thresholds and wallpaper synchronization. Built-in layouts remain under
Starting templates. No app is launched by a scene.

### Music

Settings → Music contains the independent Spotify and Apple Music integrations.
Apple Music controls the local macOS Music app, with track metadata, cached artwork,
play/pause, previous/next, shuffle, repeat and volume. Enable it explicitly and grant
macOS Automation permission when requested, then add its widget under Displays.
Both music widgets support compact and expanded views and animation data boxes.
Apple Music does not use MusicKit or stream audio inside Sorayura.

### Spotify Web

Spotify can use the desktop app or an existing Spotify Web tab in Google Chrome.
Choose the source in Settings → Music and use **Open Chrome Web Store…** on
a Store-compatible build. Login stays in Chrome; Sorayura controls the visible
player. See [setup, privacy and limitations](native-app/release/SPOTIFY-WEB.md).

Choose **Now Playing** in Settings → Music to use the active macOS media session
without a browser extension. It follows the system-selected player, so another
tab or app can replace Spotify in the widget. It shows track details and artwork
when provided, and offers play, pause, and track navigation. It uses the private
macOS MediaRemote framework, which may change across macOS releases.

AI model and project widgets paginate all locally collected entries for the chosen
period, with independent pages on each display and fewer rows in small widgets.
