# Sorayura Spotify Web — Privacy policy

Last updated: November 2, 2026

Sorayura Spotify Web is an open-source Chrome extension maintained by Aniello
Falcone as part of [Sorayura](https://github.com/AnielloFalcone/sorayura).
It connects the Spotify Web player at `https://open.spotify.com/` to the Sorayura
application installed on the same Mac.

## Information handled

While a Spotify Web tab is open, the extension reads the visible player's track
title, artist, album when available, artwork URL, track link, playback state,
volume, shuffle/repeat state and available controls. It handles music-control
requests from Sorayura, such as play, pause and next track. This is website
content and playback activity, used only to provide the requested music widget.
The extension checks matching Spotify tab URLs to find the player. It does not
collect a browsing history or monitor other websites.

The extension does not read passwords, authentication cookies, Spotify access
tokens, payment information, private messages or other browser profiles. It does
not implement Spotify login; authentication remains in the Spotify Web tab.

## Local processing and retention

Metadata and music commands travel through Chrome Native Messaging to Sorayura
on the same computer. The native host keeps one local snapshot under
`~/Library/Application Support/dev.aniello.macsystemwallpaper/spotify-web/`.
Sorayura ignores snapshots older than 15 seconds. A normal host disconnect removes
its snapshot; an interrupted or crashed connection can leave the last file on disk
until it is replaced or manually removed. No listening history is created by this
extension. Sorayura may cache the current artwork in memory.

Neither the extension nor its local bridge sends player metadata to a Sorayura
server. There are no advertisements, analytics, tracking or sales of user data.
Sorayura can download the selected artwork directly from allowed Spotify CDN
hosts. Spotify and Google independently operate their services, including the Web
player, browser and Chrome Web Store; their own privacy policies apply to them.

## Permissions

- Access to `https://open.spotify.com/*`: read the visible player and activate its
  playback controls. The extension does not have permission to run on other sites.
- `nativeMessaging`: communicate with the Sorayura companion installed on the same
  Mac. The companion accepts the allowlisted extension identity and fixed music
  commands; the extension cannot request arbitrary shell commands.

All extension JavaScript is included in its package. No remotely hosted code is
loaded. Data is used only for the extension's single purpose, never for advertising,
creditworthiness, lending or unrelated profiling, and is not sold or transferred
to unrelated parties.

## Control and removal

Close Spotify Web tabs to stop the connection, or disable/remove the extension
in Chrome's extension settings. Remove Sorayura's `spotify-web` data directory to
delete the last local snapshot and any unpacked-development export. The optional
Native Messaging registration is
`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.sorayura.spotify_web.json`.
Removing that file disconnects the companion. These steps do not change your
Spotify account or delete your Spotify library.

## Contact and changes

Questions or deletion-help requests can be submitted through
[Sorayura GitHub issues](https://github.com/AnielloFalcone/sorayura/issues).
Issues are public: do not include passwords, tokens or private listening details.
Changes to this policy will be published in this repository with an updated date.
