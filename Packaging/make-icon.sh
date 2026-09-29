#!/bin/bash
# Draws VinylQ's icon at every size macOS asks for and folds them into AppIcon.icns.
set -e
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/AppIcon.iconset"
rm -rf "$OUT"; mkdir -p "$OUT"
swift "$HERE/DrawIcon.swift" "$OUT"
iconutil -c icns "$OUT" -o "$HERE/AppIcon.icns"
rm -rf "$OUT"
echo "wrote $HERE/AppIcon.icns"
