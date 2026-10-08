# Sorayura 0.5.1 — beta

Native desktop widgets and animations for macOS, controlled from the menu bar.
The interface supports English, Italian and Spanish. In General → Language, follow the Mac’s preferred language or choose a language explicitly. System dialogs follow macOS.

- Per-monitor layouts, adjustable grid, dragging and resizing.
- System widgets with charts and history; compact or expanded memory views.
- Four animations with layers and colors linked to Mac resources.
- Presets and layout backups; optional Codex, Claude and Spotify integrations.
- Coordinated rendering across monitors and reusable Metal buffers. A short
  comparison on three displays measured approximately 30% lower CPU at similar
  frame rates. Results vary with configuration, visibility and Mac activity.

## Beta limitations

Apple Silicon package. Built for macOS 14+, tested on macOS 27.0.1; other versions
and Macs still require verification. Liquid Glass is used on macOS 26+, with
native materials on earlier versions. In-app automatic updates are not included.

Mission Control shows the synchronized static wallpaper; animations and widgets
are desktop windows. Unvisited Spaces may retain their previous wallpaper.
Memory values are estimates from system counters. Agent limits depend on available
sources and their update timestamps; missing data does not mean zero usage.

Installation from the local DMG into Applications was tested on October 8.
The user confirmed that widgets, positions and animation returned correctly
after Mission Control, monitor reconnection and sleep/wake. Diagnostics confirmed
that all three displays returned, but recorded no sleep notifications and therefore
do not verify renderer pausing during sleep. First launch of the signed and
notarized download on another Mac still requires verification.
