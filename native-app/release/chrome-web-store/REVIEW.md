# Reviewer instructions and release handoff

## Test environment

Google Chrome on an Apple silicon Mac compatible with the Sorayura release.
The extension requires the separately installed Sorayura companion and an open,
signed-in Spotify Web tab. It cannot show a track from an unopened player.
There is no Sorayura account, paid Sorayura subscription or server login.
Use the reviewer's own Spotify account; never supply a developer's credentials.
Normal Spotify account and playback restrictions remain in effect.

## Reviewer steps (after the Store ID has been integrated)

1. Install Sorayura 0.5.1 beta 9 (build 46) from
   https://github.com/AnielloFalcone/sorayura/releases/tag/v0.5.1-beta.9.
   The current public Mac builds are ad hoc signed and not Apple-notarized; the
   release documentation describes the macOS approval needed. Do not conceal this
   from reviewers. Installation in `/Applications` is recommended.
2. Open Sorayura Settings → Music. Enable Spotify, choose Spotify Web · Chrome
   and choose **Open Chrome Web Store…** once to register its local Native Messaging
   host. Installing an extension alone cannot install this native host.
3. Install the extension through the Chrome Web Store/testing link, reload
   https://open.spotify.com/ and sign in to Spotify normally.
4. Start a track in the Spotify player. The companion's settings preview should
   display its title, artist and artwork. Add the Spotify widget from Sorayura's
   Displays settings to place the same controls on the desktop.
5. Pause/resume and skip from the widget. The visible Spotify Web player should
   follow; external player changes should reach the widget. Verify volume and
   shuffle/repeat only when the Web player makes those controls available.
6. Close all Spotify Web tabs: the local connection ends and stale data is ignored.
   Open a new tab and check reconnection. Disabling the extension must stop updates.
7. If no player connects, verify the native host's allowlisted ID matches this
   Store item, its executable points into the installed companion, and the Spotify
   tab was reloaded. The toolbar badge `!` indicates missing native-host setup.

## Publication order — do not skip identity binding

1. The Store draft has Item ID `lfejofhcidmggplkmaccdbokjonncdek`. The source
   manifest contains its public key, and the native host allowlists this ID.
   The upload ZIP leaves the key out because the Store supplies the identity.
2. Test the compatible companion with a signed-in Spotify Web account using the
   keyed unpacked source before review. Check track/artwork, transport feedback,
   volume, reload, Chrome restart, missing host, tab closure, and the update path.
3. Publish the compatible Mac companion and the privacy policy, then verify both
   public URLs without sign-in. Existing Mac builds that allowlist the old
   development ID cannot connect to the Store extension.
4. Complete the listing, privacy and reviewer fields and request review.
   Use deferred publication if the companion is not yet publicly available.

## Prepared artifacts

Run from the repository root:

```
node --test native-app/Tests/SpotifyWeb.test.cjs
python3 native-app/release/chrome-web-store/prepare.py
```

Output is under `native-app/releases/chrome-web-store/1.0.0/` (ignored by Git):

- `sorayura-spotify-web-1.0.0.zip`: manifest at ZIP root; bundled scripts/icons only.
- `SHA256SUMS`: upload integrity check.
- `spotify-store.png`: 1280×800 screenshot of the real companion UI with sample data.

Regenerate the screenshot with the existing developer preview (a separate isolated
preview window; no user preferences or Spotify playback are changed):

```
native-app/build.noindex/chrome-store-check/Sorayura.app/Contents/MacOS/Sorayura --preview-spotify-widget "$PWD/native-app/releases/chrome-web-store/1.0.0"
```

Use a current bundle built with `native-app/build-native.sh`; the store variant is
captured at 1280×800. Other preview sizes are QA artifacts, not Store uploads.

Source icons, privacy, listing and review instructions are tracked separately;
none of the native app, tokens, user preferences or private logs belong in the
extension ZIP. `prepare.py` validates permissions, PNG dimensions and archive
contents, strips the development key and writes deterministic ZIP entries.

## Primary references

- https://developer.chrome.com/docs/webstore/publish
- https://developer.chrome.com/docs/webstore/images
- https://developer.chrome.com/docs/webstore/cws-dashboard-privacy
- https://developer.chrome.com/docs/extensions/reference/manifest/key
- https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging
