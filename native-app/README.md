# Sorayura — native M2

Swift, AppKit, SwiftUI and Metal implementation. See the [main README](../README.md) for features and settings.

## Build

```sh
./build-native.sh
```

Open `build/Sorayura.app`. The bundle is signed locally to preserve a valid structure; this is not a notarized distribution.

## Checks

```sh
'build/Sorayura.app/Contents/MacOS/Sorayura' --check-m1
'build/Sorayura.app/Contents/MacOS/Sorayura' --check-m2
'build/Sorayura.app/Contents/MacOS/Sorayura' --check-observation
'build/Sorayura.app/Contents/MacOS/Sorayura' --check-resources
'build/Sorayura.app/Contents/MacOS/Sorayura' --check-sampling
'build/Sorayura.app/Contents/MacOS/Sorayura' --check-agent-performance
'build/Sorayura.app/Contents/MacOS/Sorayura' --check-localization
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
