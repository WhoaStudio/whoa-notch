#!/bin/sh
# Reconstruit la bibliothèque MediaRemoteAdapter (universelle, signature ad hoc) depuis ces sources
# et la copie dans whoa-notch/Resources/MediaRemoteAdapter. Source : github.com/ungive/mediaremote-adapter
# (BSD-3), commit 0e82bf1. Pas de CMake requis : clang suffit. Extension `.bin` : Xcode ne copie
# pas un `.dylib` du groupe synchronisé dans les ressources.
#
# Le script perl exige un chemin « *.framework/<nom> » ; l'app le fabrique à l'exécution avec un
# lien symbolique vers cette bibliothèque (voir `MediaRemoteNowPlayingProvider`). On ne livre pas
# de vrai bundle .framework : le groupe synchronisé d'Xcode ne le copierait pas dans Resources.
set -eu
cd "$(dirname "$0")"
OUT=../../whoa-notch/Resources/MediaRemoteAdapter/MediaRemoteAdapter.bin
clang -fobjc-arc -fvisibility=default -dynamiclib -arch arm64 -arch x86_64 -mmacosx-version-min=26.0 \
  -Iinclude -Isrc -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.bin \
  -o "$OUT" \
  src/adapter/env.m src/adapter/get.m src/adapter/globals.m src/adapter/keys.m \
  src/adapter/now_playing.m src/adapter/repeat.m src/adapter/seek.m src/adapter/send.m \
  src/adapter/shuffle.m src/adapter/speed.m src/adapter/stream.m src/adapter/test.m \
  src/private/MediaRemote.m src/utility/Debounce.m src/utility/helpers.m
codesign --force --sign - "$OUT"
