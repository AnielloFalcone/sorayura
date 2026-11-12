# Beta preparation

The public release targets Apple Silicon. The build declares macOS 14 as its minimum;
real-world tests have been conducted on macOS 27.0.1. Intel and other macOS versions
still require verification. Review READ-ME.txt, RELEASE-NOTES.md and PRIVACY.md.

## Local candidate

From the project root:

```sh
python3 native-app/release/prepare.py candidate --version 0.5.1 --build 38
```

This creates a new folder in `native-app/releases/`, builds with hardened runtime
and a local signature, runs seven functional checks and verifies that all dependencies
are system libraries. It creates a DMG with an Applications shortcut and SHA-256
checksum. The manifest retains results, version, architecture and hashes. Existing
folders are not overwritten. A local candidate is not the public package.

The October 8 test installed the candidate from the DMG into
`/Applications/Mac System Wallpaper.app`, verifying signing and launch from that path.
This preceded the Sorayura rename. It does not simulate Gatekeeper for an Internet
download; that requires the final notarized package, with download quarantine,
on another Mac.

## Public beta without Apple membership

```sh
python3 native-app/release/prepare.py adhoc-release --version 0.5.1 --build 38
```

This runs the same build and functional checks and creates an `-ADHOC.dmg` plus
`SHA256SUMS`. It verifies the local ad hoc signature and hardened runtime, but
does not submit to Apple or claim Gatekeeper acceptance. Publish only the DMG
and checksum as a GitHub **prerelease**, with the explicit first-launch notice
in RELEASE-NOTES.md. Do not publish preparation logs, local manifests or user data.
The candidate channel remains private and the notarized `release` channel remains
available for future use. An ad hoc beta does not satisfy the Homebrew Cask generator.
A clean-Mac download/first-launch test remains outstanding and must be stated in
release notes; users may need per-app approval in Privacy & Security.

## Signing and notarization

For an unnotarized release with a reusable self-signed identity, use the same
certificate and private key in the maintainer’s Keychain for successive releases:

```sh
python3 native-app/release/prepare.py self-signed-release --stable --version 0.6.0 --build 71 \
  --identity 'CERTIFICATE_SHA1_WITHOUT_COLONS'
```

Keep an encrypted backup of the identity. Keep the existing Sparkle key and
bundle ID when rotating the app certificate, and test that update path before
publishing the feed. macOS may ask for fresh privacy consent when the certificate
changes. Mixer app and calendar selections are stored independently of consent.

### Developer ID

A **Developer ID Application** certificate and its private key must be available
in Keychain. **Apple Development** certificates cannot replace it for this
channel. Create the certificate through Apple Developer or Xcode with the
required account role. Do not export the private key into the project.

Configure notarization credentials with the secure interactive prompt from
`xcrun notarytool store-credentials`; retain only the profile name. Do not put
passwords or API keys in chat, project files or release script arguments.

```sh
python3 native-app/release/prepare.py release --version 0.5.1 --build 38 \
  --identity 'Developer ID Application: NAME (TEAMID)' \
  --notary-profile 'KEYCHAIN_PROFILE'
```

The procedure requires a Developer ID identity, enables hardened runtime and a
secure timestamp, uses only the AppleEvents entitlement needed by Spotify,
verifies all checks, notarizes and staples the app, creates/signs/notarizes the DMG,
and verifies Gatekeeper. Any result other than Accepted stops preparation.
Retain preparation.log and manifest.json.

The manifest still awaits physical verification and review of release materials
before publication. The script does not publish automatically.

## GitHub and Homebrew

Repository: **[AnielloFalcone/sorayura](https://github.com/AnielloFalcone/sorayura)**.
App and executable name: **Sorayura**.
Developer ID signing and the notarization profile still need setup. Apple signing
and notarization have not been performed on the local candidate.

Source code is public under the MIT license. Package preparation does not publish
downloads. For the notarized channel, after reviewing the materials, publish a prerelease with an immutable
tag, notarized DMG, SHA256SUMS and beta notes. The DMG includes the MIT license.
Do not upload the local candidate as the public beta.

```sh
python3 native-app/release/write-cask.py \
  native-app/releases/0.5.1-38-release/manifest.json \
  --repository AnielloFalcone/sorayura --tag v0.5.1-beta.6 \
  --output native-app/releases/sorayura.rb
```

Dedicated tap: `AnielloFalcone/homebrew-sorayura`. Preparation, Cask publication
and updates are described in [HOMEBREW.md](HOMEBREW.md).

The generator rejects local candidates and artifacts with changed checksums.
After publishing the DMG, verify the Cask in the chosen tap with a real installation.
Normal uninstall preserves data. Users should disable login and Claude connections
in the app before removing it.

Sources: [Developer ID](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/),
[Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution),
[Homebrew Cask Cookbook](https://docs.brew.sh/Cask-Cookbook).

## Sparkle update feed

Sparkle 2.10.0 is pinned in Package.resolved. Build 35 introduces the updater;
earlier builds must be upgraded manually once. The public key is embedded in
Info.plist; the private key is stored in the maintainer's login Keychain under
account `sorayura`. Keep a secure backup of that key: losing it prevents updates
for installed ad hoc builds. Never commit or upload it.

Prepare the DMG, then sign the package and feed:

```sh
python3 native-app/release/write-appcast.py native-app/releases/0.5.1-38-adhoc-release/manifest.json --tag v0.5.1-beta.6 --output updates/appcast.xml
```

The script verifies the prepared hash, matching public key and both signatures.
Upload the exact DMG and SHA256SUMS to the matching GitHub release **before**
pushing updates/appcast.xml. Do not edit signed XML; regenerate it for each release.
The feed contains the newest release only, and compares numeric CFBundleVersion:
always increase the build number. Use the plain version tag for a stable release
and a `-beta.N` tag for a beta. The public feed serves both.

Test the update on a disposable copy before declaring installation/relaunch
verified. Never remove quarantine or disable Gatekeeper as part of the updater.
Ad hoc hardened builds use entitlements-adhoc.plist to load Sparkle without a
Team ID; Developer ID builds retain library validation and re-sign nested helpers.

Spotify Web extension checks: `node --test native-app/Tests/SpotifyWeb.test.cjs`.
Native framing, schema and resource fixtures also run in `--check-m2`. Setup instructions are in [SPOTIFY-WEB.md](SPOTIFY-WEB.md).
