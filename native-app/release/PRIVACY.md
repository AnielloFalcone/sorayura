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
event/status-line connections modify local Claude configuration to receive events/status and
retain restoration information for the settings they manage.

The optional Claude account connection starts the authenticated Claude Code
client to request usage limits through its control protocol, with session
persistence disabled and without model prompts. The client contacts Anthropic
and manages authentication; Sorayura does not extract tokens. Only quota values,
timestamps and sanitized errors are retained. Organization-managed client hooks
may still apply.

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

## Update checks

When you choose Check for updates, Sparkle contacts GitHub for the signed update feed and, after confirmation, the release download. GitHub receives the network request, including your IP address and client metadata. Automatic checks, unattended updates and Sparkle system profiling are disabled. Update requests do not include your widget layouts, local agent history or account credentials.

## Spotify Web companion

The optional unpacked Chrome extension runs only on open.spotify.com and forwards visible player metadata, available controls and transport commands through Chrome Native Messaging. Cookies, login tokens and passwords remain in Chrome and are not read by the integration. A private local metadata snapshot expires after 15 seconds and is removed when its connection closes. Artwork is fetched from the allowed Spotify CDN hosts. The extension is a separate browser component; disable/remove it in Chrome to stop it. There is no Sorayura service receiving playback data. See [Spotify Web setup and limits](SPOTIFY-WEB.md).

## Now Playing

If selected as the Spotify widget source, Sorayura reads the active macOS media
session, which can belong to another app or browser tab. Track details and
artwork are kept in memory. Sorayura sends playback commands to that session
when requested and does not send its metadata to a server.

## Clipboard history

Clipboard collection is off by default. When explicitly enabled, Sorayura checks
the pasteboard change counter on its existing one-second sampling loop and stores
new text/HTTP(S) links, source-app metadata, and available RTF up to 16 KB locally. It does not recover
content copied before enable or during a pause. Confidential, transient and
auto-generated markers, known password-manager sources and user-excluded apps are
skipped. These checks cannot reliably detect unmarked passwords or every secret.

History is stored under `clipboard/history.json` in the app data directory, with a
0700 directory and 0600 file permissions, without additional application encryption.
There is no cloud sync, telemetry, URL fetch or network transmission of clipboard
contents. The archive is bounded to 8 MB; entries to 16 KB, recent history to the
configured limit and favorites to 50. No images or file contents are collected.

Disabling collection retains existing history. Clear recent items or the whole
archive (including favorites) explicitly in Clipboard settings. Clearing does not
erase the Mac's current pasteboard, and layout exports/presets do not include the
history. Source attribution uses available pasteboard metadata and the foreground
app and can be imperfect. macOS manages pasteboard consent. Cmd+C copies the selected entry with available
formatting. **Paste without formatting** writes plain text and, with Accessibility
permission, sends Cmd+V to the app that was active when the panel opened.
