#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build/RadioBar.iconset build/ModuleCache
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path "$PWD/build/ModuleCache" Tools/MakeAppIcon.swift -o build/MakeAppIcon
./build/MakeAppIcon Artwork/AppIcon.png build/AppIcon-masked.png
for size in 16 32 128 256 512; do
  sips -z "$size" "$size" build/AppIcon-masked.png --out "build/RadioBar.iconset/icon_${size}x${size}.png" >/dev/null
  double=$((size * 2))
  sips -z "$double" "$double" build/AppIcon-masked.png --out "build/RadioBar.iconset/icon_${size}x${size}@2x.png" >/dev/null
done
# iconutil may be unavailable in restricted build environments.
if ! iconutil -c icns build/RadioBar.iconset -o Resources/RadioBar.icns 2>/dev/null; then
  python3 Tools/pack-icns.py build/RadioBar.iconset Resources/RadioBar.icns
fi
echo 'Created Resources/RadioBar.icns'
