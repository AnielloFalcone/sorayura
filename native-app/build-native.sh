#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
export SWIFTPM_DISABLE_SANDBOX=1
wallpaper_version="${WALLPAPER_VERSION:-0.5.1}"
wallpaper_build="${WALLPAPER_BUILD:-18}"
wallpaper_output="${WALLPAPER_OUTPUT_ROOT:-$PWD/build.noindex}"
wallpaper_sign="${WALLPAPER_SIGN_ID:--}"
[[ "$wallpaper_version" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || { print -u2 'Invalid version'; exit 1; }
[[ "$wallpaper_build" =~ '^[0-9]+$' ]] || { print -u2 'Invalid build number'; exit 1; }
swift build --disable-sandbox -c release
app="$wallpaper_output/Sorayura.app"
mkdir -p "$app/Contents/MacOS"
mkdir -p "$app/Contents/Resources/Localization"
cp Resources/Localization/*.json "$app/Contents/Resources/Localization/"
mkdir -p "$app/Contents/Resources/Icons"
cp Resources/Icons/*.png "$app/Contents/Resources/Icons/"
# Remove legacy icon renditions from previous builds of this generated bundle.
rm -f "$app/Contents/Resources/Sorayura.icns" "$app/Contents/Resources/SorayuraAppIcon.icns" "$app/Contents/Resources/SorayuraFlatIcon.icns"
# Compile the named app icon, including asset metadata consumed by Spotlight.
xcrun actool Resources/Assets.xcassets --compile "$app/Contents/Resources" \
  --platform macosx --minimum-deployment-target 14.0 --target-device mac \
  --app-icon SorayuraAuroraIcon --output-partial-info-plist "$wallpaper_output/icon-info.plist"
cp .build/release/Sorayura "$app/Contents/MacOS/.Sorayura.new"
mv -f "$app/Contents/MacOS/.Sorayura.new" "$app/Contents/MacOS/Sorayura"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Sorayura</string>
<key>CFBundleIdentifier</key><string>dev.aniello.macsystemwallpaper.native</string>
<key>CFBundleName</key><string>Sorayura</string>
<key>CFBundleDisplayName</key><string>Sorayura</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>

<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleLocalizations</key><array><string>en</string><string>it</string><string>es</string></array>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.5.0</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><true/>
<key>NSAppleEventsUsageDescription</key><string>Mostra il brano corrente e controlla Spotify dal widget quando attivi l’integrazione.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Merge $wallpaper_output/icon-info.plist" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $wallpaper_version" "$app/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $wallpaper_build" "$app/Contents/Info.plist"
xattr -cr "$app"
wallpaper_sign_options=(--force --sign "$wallpaper_sign")
if [[ "${WALLPAPER_HARDENED:-0}" == 1 ]]; then
  wallpaper_sign_options+=(--options runtime --entitlements release/entitlements.plist)
fi
if [[ "$wallpaper_sign" != - ]]; then
  wallpaper_sign_options+=(--timestamp)
fi
codesign "${wallpaper_sign_options[@]}" "$app"
codesign --verify --deep --strict "$app"
printf '%s\n' "$app"
