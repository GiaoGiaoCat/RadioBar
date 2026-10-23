#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/ModuleCache
SOURCES=()
for source in Sources/RadioBar/*.swift; do
  if [[ "$source" != "Sources/RadioBar/RadioBarApp.swift" ]]; then
    SOURCES+=("$source")
  fi
done
xcrun swiftc -D RADIOBAR_TESTING -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path "$PWD/build/ModuleCache" -parse-as-library \
  "${SOURCES[@]}" Tools/RenderSettings.swift -o build/SettingsSnapshots
# Use a resource bundle to exercise real Info.plist reads without registering another UI app.
PREVIEW_BUNDLE="$PWD/build/SettingsMetadata.bundle"
mkdir -p "$PREVIEW_BUNDLE/Contents/Resources"
cp -X Resources/RadioBar.icns "$PREVIEW_BUNDLE/Contents/Resources/RadioBar.icns"
cp -X Resources/Sparkle-LICENSE.txt "$PREVIEW_BUNDLE/Contents/Resources/Sparkle-LICENSE.txt"
cp -X Resources/Info.plist "$PREVIEW_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundlePackageType BNDL' "$PREVIEW_BUNDLE/Contents/Info.plist"
./build/SettingsSnapshots "${1:-build/settings-previews}" "$PREVIEW_BUNDLE"
