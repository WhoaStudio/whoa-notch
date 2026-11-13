#!/bin/bash
# Construit uniquement le DMG, à partir d'une application déjà préparée.
set -euo pipefail

if [[ $# -ne 2 || ! -d "$1" || "$1" != *.app || "$2" != *.dmg ]]; then
    echo "Usage : $0 /chemin/whoa-notch.app /chemin/whoa-notch.dmg" >&2
    exit 1
fi

script_dir="$(cd "$(dirname "$0")" && pwd)"
app_path="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
app_name="$(basename "$app_path")"
mkdir -p "$(dirname "$2")"
output_dir="$(cd "$(dirname "$2")" && pwd)"
output_path="$output_dir/$(basename "$2")"
if [[ -e "$output_path" ]]; then
    echo "Le fichier existe déjà : $output_path" >&2
    exit 1
fi

work_dir="$(mktemp -d "${TMPDIR:-/tmp}/whoa-notch-dmg.XXXXXX")"
mount_path="$work_dir/volume"
mounted=false
cleanup() {
    if [[ "$mounted" == true ]]; then
        if ! hdiutil detach "$mount_path" -quiet; then
            echo "Volume encore monté ; fichiers temporaires conservés : $work_dir" >&2
            return
        fi
    fi
    rm -rf "$work_dir"
}
trap cleanup EXIT
mkdir -p "$work_dir/staging/.background" "$mount_path"

# Conserve l'application et sa signature sans les modifier.
ditto "$app_path" "$work_dir/staging/$app_name"
ln -s /Applications "$work_dir/staging/Applications"
tiffutil -cathidpicheck "$script_dir/dmg/background.png" \
    "$script_dir/dmg/background@2x.png" -out "$work_dir/staging/.background/background.tiff"
hdiutil create -volname "Whoa Notch" -srcfolder "$work_dir/staging" \
    -fs HFS+ -format UDRW "$work_dir/writable.dmg"
hdiutil attach "$work_dir/writable.dmg" -mountpoint "$mount_path" -nobrowse -noautoopen -quiet
mounted=true

# Finder enregistre le fond et la disposition dans le .DS_Store du volume.
osascript "$script_dir/dmg/layout.applescript" "$mount_path" "$app_name"
sync
hdiutil detach "$mount_path" -quiet
mounted=false
hdiutil convert "$work_dir/writable.dmg" -format UDZO \
    -imagekey zlib-level=9 -o "$work_dir/final.dmg"
hdiutil verify "$work_dir/final.dmg"
mv -n "$work_dir/final.dmg" "$output_path"
echo "DMG créé : $output_path"
shasum -a 256 "$output_path"
