#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
[[ $# == 1 ]] || { echo 'Usage : scripts/build-dmg.sh <version|vversion>' >&2; exit 1; }
version=${1#v}
python3 scripts/release-version.py "$version"
root=$PWD
output="$root/Build/release/$version"
mkdir -p "$output"
work=$(mktemp -d)
mounted=0
cleanup() {
  if [[ $mounted == 1 ]]; then hdiutil detach "$work/mount" -quiet || true; fi
  if [[ -n ${keychain:-} ]]; then security delete-keychain "$keychain" >/dev/null 2>&1 || true; fi
  rm -rf "$work"
}
trap cleanup EXIT
signed=0
# Un jeu incomplet de secrets ne doit jamais produire une signature de distribution partielle.
if [[ -n ${MACOS_CERTIFICATE_P12_BASE64:-} && -n ${MACOS_CERTIFICATE_PASSWORD:-} &&
      -n ${MACOS_SIGNING_IDENTITY:-} && -n ${APPLE_ID:-} &&
      -n ${APPLE_APP_SPECIFIC_PASSWORD:-} && -n ${APPLE_TEAM_ID:-} ]]; then
  signed=1
  keychain="$work/release.keychain-db"
  keychain_password=$(openssl rand -hex 24)
  printf '%s' "$MACOS_CERTIFICATE_P12_BASE64" | /usr/bin/base64 -D > "$work/certificate.p12"
  security create-keychain -p "$keychain_password" "$keychain" >/dev/null 2>&1
  security set-keychain-settings -lut 21600 "$keychain"
  security unlock-keychain -p "$keychain_password" "$keychain"
  security import "$work/certificate.p12" -k "$keychain" -P "$MACOS_CERTIFICATE_PASSWORD" \
    -T /usr/bin/codesign >/dev/null 2>&1
  security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
    -k "$keychain_password" "$keychain" >/dev/null 2>&1
fi
xcodebuild -project whoa-stash.xcodeproj -scheme whoa-stash -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "$root/Build/ReleaseDerivedData" \
  -skipPackagePluginValidation ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO DEVELOPMENT_TEAM= \
  MARKETING_VERSION="$version" CURRENT_PROJECT_VERSION="$version" build
app="$work/stage/whoa-stash.app"
mkdir -p "$work/stage"
ditto "$root/Build/ReleaseDerivedData/Build/Products/Release/whoa-stash.app" "$app"
[[ $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist") == "$version" ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$app/Contents/Info.plist") == "$version" ]]
architectures=$(lipo -archs "$app/Contents/MacOS/whoa-stash")
[[ " $architectures " == *" arm64 "* && " $architectures " == *" x86_64 "* ]]
# Signe d’abord les binaires imbriqués, dont MediaRemoteAdapter, puis le bundle.
while IFS= read -r -d '' binary; do
  if file -b "$binary" | /usr/bin/grep -q 'Mach-O'; then
    if [[ $signed == 1 ]]; then
      codesign --force --timestamp --options runtime --keychain "$keychain" \
        --sign "$MACOS_SIGNING_IDENTITY" "$binary"
    else
      codesign --force --sign - "$binary"
    fi
  fi
done < <(find "$app/Contents" -type f -print0)
if [[ $signed == 1 ]]; then
  codesign --force --timestamp --options runtime --keychain "$keychain" \
    --entitlements scripts/release.entitlements --sign "$MACOS_SIGNING_IDENTITY" "$app"
  ditto -c -k --keepParent "$app" "$work/notarize.zip"
  xcrun notarytool submit "$work/notarize.zip" --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID" --wait --timeout 30m
  xcrun stapler staple "$app"
  xcrun stapler validate "$app"
  status='Developer ID signed and notarized by Apple.'
else
  codesign --force --sign - "$app"
  status='Unsigned release (ad-hoc signature only), not notarized: signing/notarization secrets are missing. macOS Gatekeeper may block this download.'
fi
codesign --verify --deep --strict "$app"
dmg="$output/whoa-stash-$version.dmg"
rm -f "$dmg"
scripts/package-dmg.sh "$app" "$dmg"
if [[ $signed == 1 ]]; then
  codesign --timestamp --keychain "$keychain" --sign "$MACOS_SIGNING_IDENTITY" "$dmg"
  xcrun notarytool submit "$dmg" --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$APPLE_TEAM_ID" --wait --timeout 30m
  xcrun stapler staple "$dmg"
  xcrun stapler validate "$dmg"
fi
hdiutil verify "$dmg"
hdiutil attach "$dmg" -readonly -nobrowse -mountpoint "$work/mount" -quiet
mounted=1
[[ -d "$work/mount/whoa-stash.app" && -L "$work/mount/Applications" ]]
[[ $(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$work/mount/whoa-stash.app/Contents/Info.plist") == "$version" ]]
hdiutil detach "$work/mount" -quiet
mounted=0
(cd "$output" && shasum -a 256 "whoa-stash-$version.dmg" > SHA256SUMS)
printf '%s\n' "$status" > "$output/signing-status.txt"
echo "$status"
echo "DMG : $dmg"
