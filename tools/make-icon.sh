#!/bin/bash
# Regenerates Host/Resources/AppIcon.icns.
set -euo pipefail
cd "$(dirname "$0")/.."
TMP=$(mktemp -d)
swiftc -O tools/make-icon.swift -framework AppKit -o "$TMP/make-icon"
"$TMP/make-icon" "$TMP/AppIcon.iconset"
iconutil -c icns "$TMP/AppIcon.iconset" -o Host/Resources/AppIcon.icns
rm -rf "$TMP"
echo "-> Host/Resources/AppIcon.icns"
