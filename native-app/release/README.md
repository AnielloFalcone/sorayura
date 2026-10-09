# Beta preparation

The first beta targets Apple Silicon. The build declares macOS 14 as its minimum;
real-world tests have been conducted on macOS 27.0.1. Intel and other macOS versions
still require verification. Review READ-ME.txt, RELEASE-NOTES.md and PRIVACY.md.

## Local candidate

From the project root:

```sh
python3 native-app/release/prepare.py candidate --version 0.5.1 --build 12
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

## Signing and notarization

A **Developer ID Application** certificate and its private key must be available
in Keychain. **Apple Development** certificates cannot replace it for this
channel. Create the certificate through Apple Developer or Xcode with the
required account role. Do not export the private key into the project.

Configure notarization credentials with the secure interactive prompt from
`xcrun notarytool store-credentials`; retain only the profile name. Do not put
passwords or API keys in chat, project files or release script arguments.

```sh
python3 native-app/release/prepare.py release --version 0.5.1 --build 12 \
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
downloads. After reviewing the materials, publish a prerelease with an immutable
tag, notarized DMG, SHA256SUMS and beta notes. The DMG includes the MIT license.
Do not upload the local candidate as the public beta.

```sh
python3 native-app/release/write-cask.py \
  native-app/releases/0.5.1-12-release/manifest.json \
  --repository AnielloFalcone/sorayura --tag v0.5.1-beta.1 \
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
