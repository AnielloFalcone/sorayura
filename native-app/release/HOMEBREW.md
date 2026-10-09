# Homebrew for Sorayura

Tap: `AnielloFalcone/homebrew-sorayura`. Packages: releases of `AnielloFalcone/sorayura`.
Homebrew recognizes the `homebrew-` prefix, so users run `brew tap AnielloFalcone/sorayura`.

The initial tap contains a README, license and automated checks. `Casks/sorayura.rb`
will be added after the first signed, notarized, published and verified release.
There are no installable placeholder URLs or provisional checksums.

## First release

1. Prepare the public package with `prepare.py release`, as described in [README.md](README.md).
2. Complete verification of the final downloaded package on another Mac and publish it in a GitHub Release with an immutable tag.
3. Clone the tap locally:

   ```sh
   gh repo clone AnielloFalcone/homebrew-sorayura native-app/releases/homebrew-sorayura
   ```

4. Generate the Cask from the final local package manifest:

   ```sh
   python3 native-app/release/write-cask.py \
     native-app/releases/0.5.1-14-release/manifest.json \
     --repository AnielloFalcone/sorayura --tag v0.5.1-beta.1 \
     --output native-app/releases/homebrew-sorayura/Casks/sorayura.rb
   ruby -c native-app/releases/homebrew-sorayura/Casks/sorayura.rb
   brew style native-app/releases/homebrew-sorayura/Casks/sorayura.rb
   ```

5. Compare the checksum of the DMG downloaded from GitHub with the manifest/Cask. The generator verifies the local file; it does not certify the remote download.
6. Update the tap README to remove its preparation notice, then commit and push. The workflow checks Ruby syntax and Homebrew style without installing the app.
7. On a test Mac, verify `brew tap AnielloFalcone/sorayura`, `brew readall --os=sonoma --arch=arm AnielloFalcone/sorayura`, installation, launch, upgrade and uninstall.

When Homebrew requires explicit trust, the maintainer should review their tap
and authorize it with `brew trust --tap AnielloFalcone/sorayura` before `readall`.
Users can authorize just the individual Cask, as explained in the tap README.

Preliminary validation does not replace testing installation of the download.
The manually installed app remains active while preparing the tap.

## Updates

Use a new build number and tag for each new package. Retain published artifacts
without replacing them. The Cask uses `version "version,build"` to detect two
beta builds with the same app version.

Generate an updated Cask in a temporary file, verify it, and replace the tap’s
Cask through a commit. The generator refuses to overwrite an existing file.
Publishing to the tap is explicit. No tokens need to be stored in the repository,
and no automation writes into other repositories.

`uninstall quit:` closes the app normally during upgrades/reinstalls as well.
Data, presets and wallpapers are not automatically removed. Before uninstalling,
users disable login and Claude integrations in the app. No `zap` is provided.

## Generator verification

```sh
python3 native-app/release/test_cask.py
```

Tests use synthetic manifests and temporary files to exercise checksum validation,
format, architecture, candidate rejection, unaccepted notarization and overwrite
protection. Synthetic data is not a signed package and must not be published.

Sources: [creating a tap](https://docs.brew.sh/How-to-Create-and-Maintain-a-Tap),
[Cask Cookbook](https://docs.brew.sh/Cask-Cookbook),
[Homebrew security](https://docs.brew.sh/Homebrew-Security-and-Supply-Chain).

Preparation verification: eight generator tests passed, along with Ruby syntax
and `brew style`. A synthetic Cask was loaded with `brew info` and `brew readall`
simulating Sonoma/ARM in a temporary tap, which was subsequently removed.
No app was installed. The tap’s GitHub workflow passed on the initial skeleton;
the first real Cask will be checked when it is added.
