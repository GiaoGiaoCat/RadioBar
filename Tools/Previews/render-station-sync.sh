#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/ModuleCache
SOURCES=()
for source in Sources/RadioBar/*.swift; do
  if [[ "$source" != "Sources/RadioBar/RadioBarApp.swift" ]]; then SOURCES+=("$source"); fi
done
xcrun swiftc -D RADIOBAR_TESTING -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path "$PWD/build/ModuleCache" -parse-as-library "${SOURCES[@]}" Tools/RenderStationSync.swift -o build/StationSyncSnapshots
PREVIEW_BUNDLE="$PWD/build/StationSyncMetadata.bundle"
mkdir -p "$PREVIEW_BUNDLE/Contents/Resources"
cp -X Resources/Info.plist "$PREVIEW_BUNDLE/Contents/Info.plist"
cp -X Resources/RadioBar.icns "$PREVIEW_BUNDLE/Contents/Resources/RadioBar.icns"
cp -X Resources/Sparkle-LICENSE.txt "$PREVIEW_BUNDLE/Contents/Resources/Sparkle-LICENSE.txt"
/usr/libexec/PlistBuddy -c 'Set :CFBundlePackageType BNDL' "$PREVIEW_BUNDLE/Contents/Info.plist"
./build/StationSyncSnapshots "${1:-build/station-sync-previews}" "$PREVIEW_BUNDLE"
