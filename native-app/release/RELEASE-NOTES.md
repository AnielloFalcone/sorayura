# Sorayura 0.5.1-beta.6 — build 38

Native desktop widgets and animations for macOS, controlled from the menu bar.
The interface supports English, Italian and Spanish. In General → Language, follow the Mac’s preferred language or choose a language explicitly. System dialogs follow macOS.

- Per-monitor layouts, adjustable grid, dragging and resizing. Widget edit handles support continuous per-display dimensions, with snapping when the grid is enabled.
- System widgets with charts and history; compact or expanded memory views.
- Animations with layers and colors linked to Mac resources and available AI quotas. Four independently configurable data cards can show summaries from all widgets.
- Presets and layout backups; optional Codex, Claude and Spotify integrations.
- Coordinated rendering across monitors and reusable Metal buffers. A short
  comparison on three displays measured approximately 30% lower CPU at similar
  frame rates. Results vary with configuration, visibility and Mac activity.

## Fixed in beta 6

The native title bar now follows the dark Glass appearance and the content extends behind it, removing the separate light strip.

## New and fixed in beta 5

- Layout and animation edits, Space changes and wake recovery no longer force the system wallpaper to be reapplied. Missing custom images cannot silently become a default gradient; newly selected images are copied to Sorayura's persistent storage.
- Spotify Web in Chrome is available as an optional source through a bundled unpacked extension. Login and audio stay in Chrome. Run setup in Settings → Integrations, then load the extension in Chrome. This is a first beta; live authenticated Spotify Web playback still needs validation. See the included SPOTIFY-WEB.md.
- AI Models and Projects can page through all locally collected entries for the selected period. Pages are independent per monitor, and their row count adapts to widget height.
- Settings uses a transparent native glass window and sidebar, with the existing material fallback on older macOS versions.
- The menu item is now Settings… (localized).

## Fixed in beta 4

Widget and animation dragging now uses the fixed desktop coordinate space. Edge-clamped widgets start from their visible position, and grid snapping stays inside the display. Desktop surfaces are explicitly assigned to their display and no longer accept automatic window constraints, SwiftUI sizing or safe-area insets. Reconnected display IDs refresh the associated content, and startup performs a delayed geometry recovery.

Geometry and movement regression checks passed, including negative display origins and real window frames on the connected displays. The reported offset on a separate tester's monitor arrangement still requires confirmation there.

## New in beta 3

General settings now include “Check for updates…”. Updates and their feed are signed with Sorayura's Ed25519 key and hosted on GitHub. Checks are manual; installation requires confirmation. Preferences are saved before relaunch. Sparkle is included under its open-source license.

The ad hoc build disables library validation so it can load the signed Sparkle framework without an Apple Team ID; hardened runtime remains enabled. This does not provide Apple notarization.

## Fixed in beta 2

Fresh installations now keep the existing macOS wallpaper on each display. Widgets and animations are overlaid without replacing the system wallpaper. Select a Sorayura background explicitly in Wallpaper settings; synchronization with macOS starts disabled. Existing saved wallpaper preferences are preserved, so upgrading from beta 1 does not automatically restore a previous wallpaper.

## Beta limitations

Apple Silicon package. Built for macOS 14+, tested on macOS 27.0.1; other versions
and Macs still require verification. Liquid Glass is used on macOS 26+, with
native materials on earlier versions. Updates can be checked manually from General settings. Sparkle downloads and installs an update after confirmation.

Mission Control shows the synchronized static wallpaper; animations and widgets
are desktop windows. Unvisited Spaces may retain their previous wallpaper.
Memory values are estimates from system counters. Agent limits depend on available
sources and their update timestamps; missing data does not mean zero usage.

Installation from the local DMG into Applications was tested on October 8.
The user confirmed that widgets, positions and animation returned correctly
after Mission Control, monitor reconnection and sleep/wake. Diagnostics confirmed
that all three displays returned, but recorded no sleep notifications and therefore
do not verify renderer pausing during sleep. First launch of this downloaded package on another Mac still requires verification.

## Download and first launch

This prerelease is **ad hoc signed, not Developer ID signed and not notarized by Apple**. Download the DMG, drag Sorayura into Applications, eject the image and open the app. If macOS blocks it, use System Settings → Privacy & Security → Open Anyway for this app, following [Apple’s instructions](https://support.apple.com/en-ie/102445). Managed Macs may prohibit this exception. Do not disable Gatekeeper globally.

`SHA256SUMS` identifies the uploaded DMG. Users of beta 3 can update in the app. Users of beta 1 or beta 2 must install this build manually once. The Homebrew Cask is not available for this unsigned-by-Developer-ID channel.

Claude account limits use the authenticated CLI control protocol with session persistence disabled. Spotify includes expanded controls and shortcuts. Account integrations are optional and require their respective clients and login.
