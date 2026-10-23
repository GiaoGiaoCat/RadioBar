#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
PLATFORM="${1:-macos}"
mkdir -p build/ModuleCache
SOURCES=(Sources/RadioBar/StationSyncDirectory.swift Tools/DirectoryProbe/DirectoryProbe.swift)
case "$PLATFORM" in
  macos) SDK=macosx; TARGET=arm64-apple-macosx14.0; APP="$PWD/build/RadioBarDirectoryProbe-macOS.app"; EXEC="$APP/Contents/MacOS"; PLIST="$APP/Contents/Info.plist" ;;
  ios-simulator) SDK=iphonesimulator; TARGET=arm64-apple-ios17.0-simulator; APP="$PWD/build/RadioBarDirectoryProbe-iOS-Simulator.app"; EXEC="$APP"; PLIST="$APP/Info.plist" ;;
  ios-device) SDK=iphoneos; TARGET=arm64-apple-ios17.0; APP="$PWD/build/RadioBarDirectoryProbe-iOS-Device.app"; EXEC="$APP"; PLIST="$APP/Info.plist" ;;
  *) echo 'Usage: build-directory-probe.sh [macos|ios-simulator|ios-device]' >&2; exit 2 ;;
esac
mkdir -p "$EXEC"
xcrun --sdk "$SDK" swiftc -swift-version 5 -target "$TARGET" -sdk "$(xcrun --sdk "$SDK" --show-sdk-path)" \
  -module-cache-path "$PWD/build/ModuleCache" -parse-as-library "${SOURCES[@]}" -o "$EXEC/DirectoryProbe"
cat > "$PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>local.victor.RadioBar.DirectoryProbe</string>
<key>CFBundleName</key><string>RadioBar Directory Probe</string>
<key>CFBundleExecutable</key><string>DirectoryProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>CFBundleVersion</key><string>1</string>
</dict></plist>
PLIST
if [[ "$PLATFORM" == macos ]]; then
  /usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 14.0' "$PLIST"
  codesign --force --sign - "$APP"
  codesign --verify --deep --strict "$APP"
else
  /usr/libexec/PlistBuddy -c 'Add :MinimumOSVersion string 17.0' "$PLIST"
  /usr/libexec/PlistBuddy -c 'Add :UIDeviceFamily array' "$PLIST"
  /usr/libexec/PlistBuddy -c 'Add :UIDeviceFamily:0 integer 1' "$PLIST"
  /usr/libexec/PlistBuddy -c 'Add :LSSupportsOpeningDocumentsInPlace bool true' "$PLIST"
  /usr/libexec/PlistBuddy -c 'Add :UILaunchScreen dict' "$PLIST"
  /usr/libexec/PlistBuddy -c 'Add :UIApplicationSceneManifest dict' "$PLIST"
  /usr/libexec/PlistBuddy -c 'Add :UIApplicationSceneManifest:UIApplicationSupportsMultipleScenes bool false' "$PLIST"
  if [[ "$PLATFORM" == ios-simulator ]]; then codesign --force --sign - "$APP"; fi
fi
echo "Prepared: $APP"
if [[ "$PLATFORM" == ios-device ]]; then
  echo 'Unsigned device artifact only. Use Tools/DirectoryProbe/DirectoryProbe.xcodeproj with your own Personal Team to sign/install; this script does not install or change signing accounts.'
fi
