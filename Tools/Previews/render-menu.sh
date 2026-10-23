#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/ModuleCache
python3 Tools/PrepareMenuPreview.py build/CapturedMenuPreview.swift
SOURCES=()
for source in Sources/RadioBar/*.swift; do
  if [[ "$source" != "Sources/RadioBar/RadioBarApp.swift" && "$source" != "Sources/RadioBar/RadioPlayer.swift" ]]; then
    SOURCES+=("$source")
  fi
done
xcrun swiftc -D RADIOBAR_TESTING -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path "$PWD/build/ModuleCache" -parse-as-library \
  "${SOURCES[@]}" build/PreviewRadioPlayer.swift build/CapturedMenuPreview.swift -o build/MenuSnapshots
if [[ "${1:-}" == "--interactive" ]]; then
  APP="$PWD/build/RadioBarMenuPreview.app"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp -X build/MenuSnapshots "$APP/Contents/MacOS/MenuSnapshots"
  cp -X Resources/Info.plist "$APP/Contents/Info.plist"
  cp -X Sources/RadioBar/Resources/stations.default.json "$APP/Contents/Resources/stations.default.json"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable MenuSnapshots' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.victor.RadioBar.MenuPreview' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleName RadioBar Menu Preview' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName RadioBar Menu Preview' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :LSUIElement false' "$APP/Contents/Info.plist"
  codesign --force --sign - "$APP"
  echo "Prepared: $APP"
else
  ./build/MenuSnapshots "${1:-build/menu-previews}"
fi
