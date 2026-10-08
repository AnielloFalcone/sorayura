# Performance and verification

Local tests were conducted on an Apple Silicon Mac running macOS 27.0.1 with three monitors. These results are not a guarantee for other configurations.

During the latest ten-minute observation of version 0.5.1, build 2, the process remained active with an unchanged configuration. Over the final three minutes: median CPU was 14.3% of one core, median physical footprint was 367 MiB and median RSS was 197.5 MiB. Renderers maintained approximately 29–30 fps across the three monitors. Recorded GPU timings cover only the app’s commands and do not measure energy, WindowServer or total GPU usage.

Earlier one-hour tests observed stable memory within the recorded interval. Fluctuations and caches neither prove nor rule out a leak. Visibility and screen lock were not monitored throughout, so CPU values cannot be attributed entirely to the optimizations.

The user tested Mission Control, monitor disconnection/reconnection and sleep/wake, confirming that widgets, positions and animation returned correctly. These physical tests preceded the Sorayura rename.

Package preparation runs seven checks: M1, M2, observation, resources, sampling, agent reader performance and localization. Integrations requiring consent or external app data, launch at login and installation of a notarized download on another Mac require real-world verification.

Raw test data remains local and is excluded from the public repository.
