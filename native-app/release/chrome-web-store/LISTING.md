# Chrome Web Store listing — English

## Name

Sorayura Spotify Web

## Short description

Control Spotify Web from Sorayura’s music widgets on your Mac.

## Detailed description

Bring your existing Spotify Web player to your Mac desktop with Sorayura.

This companion extension connects the Spotify tab already open in Chrome to
Sorayura's music widgets. Your Spotify login stays in the browser.

• See the current track, artist and artwork on your desktop.
• Play or pause, skip tracks and adjust the Spotify player's volume.
• Use shuffle and repeat when available in Spotify Web.
• Choose compact or expanded widgets in Sorayura, with shortcuts to Spotify links.
• Keep the connection local to your Mac, without a Sorayura account or server.

REQUIRES THE SORAYURA MAC APP
This extension is a companion, not a standalone player. Install a compatible
Sorayura release from https://github.com/AnielloFalcone/sorayura/releases,
then open Settings → Music, enable Spotify, select Spotify Web · Chrome and
connect the extension. Keep a Spotify Web tab open and reload it after installing
the extension. Sorayura's current Mac builds require Apple silicon.

The extension reads the visible Spotify player and operates its existing
controls. It does not stream audio independently, bypass Spotify subscription or
playback restrictions, read your password or access authentication cookies.
Available controls depend on Spotify, your account and the current player.
Spotify can change its website, which may require an extension update.

Open source under the MIT license. No advertising or analytics.
Sorayura is an independent project, not affiliated with or endorsed by Spotify,
Google or Apple.

## Dashboard fields

- Language: English
- Category: Entertainment.
- Price: Free
- Homepage: https://github.com/AnielloFalcone/sorayura
- Support: https://github.com/AnielloFalcone/sorayura/issues
- Privacy policy: https://github.com/AnielloFalcone/sorayura/blob/main/native-app/release/chrome-web-store/PRIVACY.md
- Icon: `Resources/SpotifyWebExtension/icons/icon128.png`
- Screenshot: `releases/chrome-web-store/1.0.0/spotify-store.png`

Publish the privacy document to the public repository and check that its URL
works without sign-in BEFORE submitting. The screenshot is a capture of the actual
Sorayura companion widget rendered with a clearly named sample track, not evidence
of a completed authenticated Spotify Web playback test. Do not add ratings, claims
of Spotify endorsement, invented browser UI or confidential desktop screenshots.

## Privacy practices — copy-ready answers

### Single purpose

Connect the Spotify Web player in Chrome to Sorayura's local Mac music widgets
so users can see the current track and operate the player's existing controls.

### nativeMessaging justification

Required to send current player metadata to the Sorayura companion on the same
Mac and receive fixed music-control requests. The companion is installed with
Sorayura and registers a Native Messaging host allowlisting this extension ID.
There is no remote server or arbitrary command-execution interface.

### Host permission justification

Access is limited to https://open.spotify.com/* to read the visible player and
activate its playback buttons. Matching tab URLs are used to find the open player.
No access to unrelated websites, browser history, cookies or credentials is requested.

### Remote code

No. All executable extension code is bundled in the submitted package. Spotify
artwork is image data, not code. Native Messaging communicates with the separately
installed, open-source Sorayura companion.

### Data handling

Declare **Website content** (track metadata, artwork URL and track link) and
**User activity** limited to music playback state and requested music controls.
Data is processed locally for the music widget. Do not claim that no user data is
handled simply because there is no remote collection. No identity, health,
financial, authentication, personal communications, location or general web
history data is collected. Confirm the current dashboard definitions against
this policy when submitting; do not certify unrelated categories by default.

Data is not sold, used for unrelated purposes or used for creditworthiness or
lending. The developer must personally confirm the dashboard certifications after
reviewing these statements and the actual build.
