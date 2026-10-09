# Sorayura — native M2

Swift, AppKit, SwiftUI and Metal implementation. See the [main README](../README.md) for features and settings.

## Build

```sh
./build-native.sh
```

Open `build.noindex/Sorayura.app`. The bundle is signed locally to preserve a valid structure; this is not a notarized distribution.

## Checks

```sh
'build.noindex/Sorayura.app/Contents/MacOS/Sorayura' --check-m1
'build.noindex/Sorayura.app/Contents/MacOS/Sorayura' --check-m2
'build.noindex/Sorayura.app/Contents/MacOS/Sorayura' --check-observation
'build.noindex/Sorayura.app/Contents/MacOS/Sorayura' --check-resources
'build.noindex/Sorayura.app/Contents/MacOS/Sorayura' --check-sampling
'build.noindex/Sorayura.app/Contents/MacOS/Sorayura' --check-agent-performance
'build.noindex/Sorayura.app/Contents/MacOS/Sorayura' --check-localization
```

Checks requiring interaction with the Mac are documented in [PERFORMANCE.md](PERFORMANCE.md).

Observation checks use an isolated model: a CPU sample must not notify settings, agents, Spotify or unchanged metrics. They also check history, warnings and control bindings. They do not start integration readers or write user preferences.

Resource checks create hidden settings windows and small test buffers. They verify view release, reopening with the same section and geometry, a maximum of three frames in flight, buffer reuse/growth, GPU completion and geometry for the four styles. They do not start the wallpaper or change preferences.

They also verify pause/resume, attaching/detaching the Metal view, reference vertices from the previous release, identical GPU pixels between separate and grouped draws, and restoration of diagnostic phases. Sampling uses simulated disk readings to verify cache expiry, error handling and immediate refresh after reset. CPU/memory/network continue sampling every second; disk space is read every 30 seconds and after wake/reset.

Resource checks additionally cover the shared clock with renderers at different frame rates and a three-pass GPU batch: slots retained until completion, released when a batch is abandoned, and correct independent pixels. Pausing for sleep/inactive sessions or when all windows are occluded is tested with simulated states. These fixtures do not certify physical Mac transitions.

## Multi-monitor rendering

Normal launches coordinate renderers through a shared clock and submit passes due in the same tick through one Metal command buffer. Each monitor retains its own FPS limit and buffers. This optimization does not automatically reduce quality or change preferences.

`--independent-frames` is an internal comparison flag that restores separate automatic MTKView clocks in the same binary. It is a launch option rather than a UI setting. To compare modes, quit the existing instance normally before launching the exact bundle with the flag. Resource checks also support `--independent-frames --check-resources` without starting the desktop.

In shared rendering, `MTKView.isPaused` is always true because drawing is explicit. Snapshots distinguish `automatic_mtk_paused` from the logical `paused` state and add `frame_clock`, ticks and shared submissions. Use submitted-frame counters to verify that animation is active. Sleep, inactive sessions or occlusion of all active wallpaper windows suspend the clock. Physical resume verification is documented in PERFORMANCE.md.

## Component diagnostics

`--benchmark-sampling` compares a few serial reader samples with repeated and cached disk queries. `--benchmark-geometry` measures small CPU fixtures for the four geometries. These commands do not create wallpaper windows, read agent data or write preferences. They are not full-app comparisons or GPU/energy measurements.

Launching with `--profile-components /absolute/path/folder` enables an explicit visual test lasting approximately nine minutes: six 90-second phases (normal, Metal paused, Glass replaced, widgets hidden, widgets hidden + Metal paused, normal). Phase boundaries are recorded in component-profile.json. It does not save preference changes, retains the Metal view and timeline, and automatically restores normal presentation. Editing layouts/preferences, display/Space changes or wake interrupt and restore it. Use an unlocked Mac with controlled visibility, after agreeing to the temporary presentation changes. Collect CPU/RSS/footprint for the PID simultaneously, exclude transition samples and distinguish process cost from GPU/WindowServer cost. An existing instance does not automatically start a second test.

`--render-diagnostics /absolute/path/file.json` enables passive snapshots every ten seconds for approximately ten minutes, recording draw/submitted-frame counters and Metal view state across monitors. It does not change the desktop or preferences. Check zero-frame intervals, occlusion and pause before interpreting lower CPU as renderer savings. Counters do not measure GPU/energy cost or pixel visibility. Normal launches do not enable this collection.

Since 0.5.1, snapshots also include GPU timings for this app’s command buffers, completion errors, windows/displays and the last 64 Space, monitor and suspension events. `--render-diagnostics-seconds 1800` extends collection, up to one hour. GPU timings are not total GPU utilization percentages or energy consumption. Recent timing statistics retain at most 240 samples and do not collect window contents.

For an authorized component test, `performance/measure-footprint.py` accepts `--render-health <file.json>` and retains new snapshots in render-snapshots.jsonl. After the profile restores normal presentation, `python3 performance/analyze-components.py <test-folder>` calculates CPU/RSS/footprint per phase, excludes the first 30 and last five seconds, and checks renderer presence, pause and frame submissions for each monitor. Interpret short sequences with cache/phase-order effects and the initial/final full-app comparison in mind. This does not measure GPU cost or energy.

For two three-minute collections in `independent/` and `shared/` with metadata and snapshots, `python3 performance/analyze-renderer.py <test-folder>` compares CPU/RSS/footprint over seconds 60–175, including only CPU intervals fully within that segment. It checks process identity/configuration, active renderers, equivalent dimensions and FPS (ratio 0.95–1.05). The October 8 comparison observed approximately 30% lower CPU, with no demonstrated RAM savings; longer-term confirmation is needed. See PERFORMANCE.md for the published verification summary.

M2 features and data limitations: [M2.md](M2.md).

## Localization

The native interface supports English, Italian and Spanish. General → Language offers System, English, Italiano and Español; a change updates the app’s views, menu bar and widget menus immediately. System selection uses the first supported language in the Mac’s preferred language list, with English as fallback. Dates and numbers use that language with the Mac’s region. System dialogs and permission prompts follow macOS.

The language choice is stored separately in UserDefaults, rather than in exported layouts or presets. Existing widget IDs, settings files and custom preset names remain unchanged. Restart after changing macOS language/region preferences when following the system.

Translation catalogs are `Resources/Localization/en.json`, `it.json` and `es.json`. Keys retain the original interface wording so stored identifiers stay stable. Use `L` for fixed text and `LF` for interpolated messages; numbered `{0}` placeholders can be reordered but must be preserved. Leave user data (track names, project names, custom preset names) untouched. Catalogs and the resolved locale are cached outside the render loop. `build-native.sh` bundles all supported catalogs; run `--check-localization` from the app bundle to validate resources and placeholders. To add a language, add its catalog and register it in `Localizer.supported`, the language picker and `CFBundleLocalizations`.

## Widget resizing

In Edit Layout, drag the right handle for width, the bottom handle for height, or the corner for both. Free placement retains continuous sizes in logical screen points; grid placement snaps dimensions to cells. The top-left corner stays anchored and resizing stops at the display edge. Custom dimensions are saved separately for each display, included in saved presets and layout exports, and remapped when importing on another Mac. Built-in presets restore their predefined sizes. Unit selectors remain available; changing an axis preserves custom dimensions on the other axis. Old settings without custom dimensions continue using unit sizes.

## Animation interaction

Outside edit mode, animation and readout areas accept the same secondary click and 0.55-second hold-to-drag gesture as widgets. The animation menu offers Edit Layout, its four styles and Remove (on that display). Dragging follows grid settings and saves its center per display. Widget controls take precedence over the animation when they overlap. Hidden or disabled animations have no hit window. Edit mode retains its existing drag and resize controls.

## Animation data boxes

Animation → Data boxes configures independent right, left, top and bottom cards. Select a side, then choose its fields; an empty selection hides that card. All widget summaries are available, including clock, hostname, uptime, thermal state, application presence, Spotify, AI token totals, the leading model/project, recent/live activity and API-value estimates. AI activity summarizes active days in the last 13 weeks. Existing integration opt-ins remain required, and these cards use cached readings from the existing services. They do not start new integrations or read credentials.

Animated layers are selected separately: CPU, memory, disk, network, battery and Claude/Codex session/weekly limits. Non-numeric fields have no percentage bar or animated layer. Missing/expired limits do not become zero usage; quota readings older than 30 minutes are labeled stale and do not drive animation. API values remain estimates/session values, not invoices or subscription spend. If there are only informational cards, Metal animation is hidden and its frame clock is paused.

Cards wrap into columns when needed and are bounded by each screen. Clickable areas include the visual and each card; the transparent gaps pass through. Open Data boxes… from the animation context menu to configure them. Preferences, saved presets and exports retain selections; old layouts initially keep their selected resource values on the right. Built-in presets restore that default.

### Smooth wallpaper gradients

Generated Aurora and Midnight backgrounds render once in sRGB at the display's pixel resolution, up to a 4096-pixel longest edge. Smooth radial falloff and deterministic sub-LSB dithering reduce visible contours in dark gradients. The same raster is used in the app and saved losslessly as PNG for the macOS desktop, preserving the dithering in Mission Control. Backgrounds remain static and cached, with up to four entries and a 96 MiB bitmap budget; this adds no per-frame noise pass. User-selected image files are not modified.
