#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/ModuleCache
SOURCES=()
for source in Sources/RadioBar/*.swift; do
  if [[ "$source" != "Sources/RadioBar/RadioBarApp.swift" ]]; then SOURCES+=("$source"); fi
done
xcrun swiftc -D RADIOBAR_TESTING -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path "$PWD/build/ModuleCache" -parse-as-library \
  "${SOURCES[@]}" Tests/NativeChannelDropTests.swift -o build/NativeChannelDropTests
if [[ "${1:-}" == "--interactive" || "${1:-}" == "--interactive-visibility" || "${1:-}" == "--interactive-editor" ]]; then
  rm -f build/native-channel-drag-result.txt
  APP="$PWD/build/RadioBarDragTests.app"
  mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
  cp -X build/NativeChannelDropTests "$APP/Contents/MacOS/NativeChannelDropTests"
  cp -X Resources/Info.plist "$APP/Contents/Info.plist"
  cp -X Sources/RadioBar/Resources/stations.default.json "$APP/Contents/Resources/stations.default.json"
  cp -X Resources/RadioBar.icns "$APP/Contents/Resources/RadioBar.icns"
  cp -X Resources/Sparkle-LICENSE.txt "$APP/Contents/Resources/Sparkle-LICENSE.txt"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable NativeChannelDropTests' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.victor.RadioBar.DragTests' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleName RadioBar Drag Tests' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName RadioBar Drag Tests' "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c 'Set :LSUIElement false' "$APP/Contents/Info.plist"
  if [[ "${1:-}" == "--interactive-visibility" ]]; then
    rm -f build/native-station-visibility-result.txt
    /usr/libexec/PlistBuddy -c 'Add :RadioBarVisibilityFeedbackTest bool true' "$APP/Contents/Info.plist"
  fi
  if [[ "${1:-}" == "--interactive-editor" ]]; then
    rm -f build/native-station-editor-result.txt
    /usr/libexec/PlistBuddy -c 'Add :RadioBarStationEditorTest bool true' "$APP/Contents/Info.plist"
  fi
  codesign --force --sign - "$APP"
  echo "Prepared: $APP"
else
  ./build/NativeChannelDropTests
fi
