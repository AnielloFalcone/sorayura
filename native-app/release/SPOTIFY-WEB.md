# Spotify Web in Chrome

Sorayura can control either the Spotify desktop app or Spotify Web in Google
Chrome. The Web option uses a small local extension, not Spotify's Web API.
Playback and login stay in the existing Spotify tab. Sorayura is a controller;
it does not stream audio itself.

## One-time setup

1. In Sorayura Settings → Music, enable Spotify and choose **Spotify Web · Chrome**.
2. Choose **Set up Chrome extension…**. Sorayura registers its local Native Messaging
   host and opens a folder containing the extension.
3. In Chrome, open `chrome://extensions`, turn on **Developer mode**, choose
   **Load unpacked**, and select that folder.
4. Reload the tab at `https://open.spotify.com/` and start playback normally.

The first beta is an unpacked extension; it has not been published to the Chrome
Web Store. Install and keep Sorayura in Applications before setup. If the app is
moved, run setup again. If a future release changes the extension, run setup again
and use **Reload** on its Chrome extension card.

## Behavior and limits

- The widget supports the playback controls currently available in Spotify Web.
  Unavailable controls are disabled; Spotify still determines subscription and
  playback restrictions. Player volume changes only the Spotify Web player.
- Track changes are observed and a two-second heartbeat keeps the connection
  fresh. Commands travel immediately through Chrome Native Messaging.
- With multiple Spotify tabs, the extension prefers a playing tab, then an active
  one. With multiple Chrome profiles, the most recently reporting connection wins.
  Profile selection is not included in this first version.
- Favorites open their Spotify links in Chrome. They do not bypass Spotify's
  playback or autoplay rules.
- This integration relies on Spotify Web's visible player controls. Spotify can
  change those controls; authenticated playback still needs testing against the
  tester's browser and Spotify account. English, Italian and Spanish pause labels
  are recognized; unsupported/missing controls may not be detected.

## Privacy and removal

The extension can run only on `open.spotify.com`. It reads the visible player
metadata and uses the player buttons; it does not read cookies, access tokens or
passwords. It makes no requests to a Sorayura server. Artwork is fetched directly
from the existing allowed Spotify CDN hosts. The local native host accepts only
this extension ID and a fixed set of music controls. It keeps one private, short-lived
metadata snapshot, not a listening history.

The extension remains a separate Chrome component while installed, even if the
Sorayura window is closed. Disable or remove it from `chrome://extensions` to stop
the browser connection. The user-specific host registration is at
`~/Library/Application Support/Google/Chrome/NativeMessagingHosts/dev.sorayura.spotify_web.json`;
the exported extension is under Sorayura's `spotify-web/Chrome extension` data folder.
These may be removed after removing the extension. No browser-wide JavaScript
from Apple Events setting is required or changed.

## Future OAuth option

A Spotify OAuth integration remains a separate possible route for account-based
control. It is not implemented here. Before adding it, recheck Spotify's Premium,
Development Mode user limits and public quota requirements:
[Spotify quota modes](https://developer.spotify.com/documentation/web-api/concepts/quota-modes).

## Chrome Web Store preparation

The upload package, listing copy, privacy policy, reviewer instructions and final
Store-ID binding steps are documented in
[the publication handoff](chrome-web-store/REVIEW.md). The extension is not yet
published; the unpacked setup above remains the beta path until the Store assigns
an ID and a matching companion release is available.
