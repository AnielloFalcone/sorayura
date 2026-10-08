# Data and integrations

The app stores preferences, presets, wallpapers and local summaries in
`~/Library/Application Support/dev.aniello.macsystemwallpaper/`. Widgets read
system counters such as CPU, memory, battery, disk, network and thermal state.
There is no developer-operated telemetry service or app account system.

When AI agents are enabled, the app reads local Codex/Claude logs to derive
usage, models, projects and activity. Original logs may contain conversation
content; they are processed locally. When enabled, the Codex account connection
starts the user-selected CLI with its existing authentication. The CLI may
contact OpenAI services to retrieve limits. The app does not ask for a password
or API key in its own settings.

Claude desktop limits use locally available Claude app data. Optional Claude
connections modify local Claude configuration to receive events/status and
retain restoration information for the settings they manage.

Spotify uses AppleEvents after macOS consent. Track, artist and playback are
read from the Spotify app; artwork is downloaded over HTTPS from allowed
Spotify CDN domains. These requests expose standard network information,
such as the IP address, to the provider. Permissions can be revoked in macOS settings.

Exported backups include layouts and the wallpaper image; consider their
contents before sharing. Uninstalling preserves local data. To remove it,
explicitly delete the data folder after disabling login and Claude connections.

Development diagnostics require explicit launch options, write local
resource/renderer counters and monitor identifiers, and have a limited duration.
They are not automatically sent to the developer.
