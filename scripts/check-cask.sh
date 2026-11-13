#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Homebrew exige un nom de cask issu d’un tap plutôt qu’un chemin de fichier.
work=$(mktemp -d)
export XDG_CONFIG_HOME="$work/config"
tap="whoastudio/release-check-$$"
path="$(brew --repository)/Library/Taps/${tap%/*}/homebrew-${tap#*/}"
mkdir -p "$(dirname "$path")"
[[ ! -e $path ]]
ln -s "$PWD" "$path"
trap 'rm -f "$path"; rm -rf "$work"' EXIT
if brew help trust >/dev/null 2>&1; then
  brew trust --cask "$tap/whoa-notch"
fi
brew audit --cask --strict "$tap/whoa-notch"
brew style "$PWD/Casks/whoa-notch.rb"
