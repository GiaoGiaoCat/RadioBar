#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mode="${1:-}"
if [[ $# -gt 1 || ( -n "$mode" && "$mode" != "--developer-id" ) ]]; then
  echo 'Usage: ./build.sh [--developer-id]' >&2
  exit 2
fi
if [[ "$mode" == "--developer-id" && -z "${RADIOBAR_SIGNING_IDENTITY:-}" ]]; then
  echo 'Set RADIOBAR_SIGNING_IDENTITY to a Developer ID Application identity.' >&2
  exit 2
fi
source Tools/sparkle-config.sh
mkdir -p build/ModuleCache
# Stage outside cloud-synced folders so File Provider metadata cannot break signing.
STAGE="$(mktemp -d /private/tmp/RadioBar-build.XXXXXX)"
# Keep the new archive on the destination filesystem so the final rename replaces
# the old file, including its quarantine metadata, only after packaging succeeds.
ARCHIVE_STAGE="$(mktemp -d "$PWD/build/RadioBar-package.XXXXXX")"
trap 'rm -rf "$STAGE" "$ARCHIVE_STAGE"' EXIT
APP="$STAGE/RadioBar.app"
ARCHIVE="$ARCHIVE_STAGE/RadioBar-macOS-arm64.zip"
DESTINATION="build/RadioBar-macOS-arm64.zip"
if [[ "$mode" == "--developer-id" ]]; then
  DESTINATION="build/RadioBar-notary-submission.zip"
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
./Tools/prepare-builtin-streams.sh "$STAGE/BuiltinStreams"
cp -X "$STAGE/BuiltinStreams/builtin-streams.bin" "$APP/Contents/Resources/builtin-streams.bin"
./Tools/fetch-sparkle.sh
SDK="$(xcrun --sdk macosx --show-sdk-path)"
xcrun swiftc -swift-version 5 -O -whole-module-optimization \
  -target arm64-apple-macosx14.0 -sdk "$SDK" \
  -module-cache-path "$PWD/build/ModuleCache" \
  -F "$SPARKLE_ROOT" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  -parse-as-library Sources/RadioBar/*.swift "$STAGE/BuiltinStreams/BuiltinStreamKey.swift" \
  -o "$APP/Contents/MacOS/RadioBar"
cp -X Sources/RadioBar/Resources/stations.default.json "$APP/Contents/Resources/stations.default.json"
cp -X Resources/RadioBar.icns "$APP/Contents/Resources/RadioBar.icns"
cp -X Resources/Sparkle-LICENSE.txt "$APP/Contents/Resources/Sparkle-LICENSE.txt"
cp -X Resources/Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Frameworks"
/usr/bin/ditto --norsrc "$SPARKLE_ROOT/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# Keep the bundled Sparkle helper signatures intact; sign the host last.
plutil -lint "$APP/Contents/Info.plist"
if [[ "$mode" == "--developer-id" ]]; then
  FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
  VERSION="$FRAMEWORK/Versions/B"
  for component in "$VERSION/XPCServices/Installer.xpc" "$VERSION/Autoupdate" "$VERSION/Updater.app"; do
    codesign --force --timestamp --options runtime --sign "$RADIOBAR_SIGNING_IDENTITY" "$component"
  done
  codesign --force --timestamp --options runtime --preserve-metadata=entitlements --sign "$RADIOBAR_SIGNING_IDENTITY" "$VERSION/XPCServices/Downloader.xpc"
  codesign --force --timestamp --options runtime --sign "$RADIOBAR_SIGNING_IDENTITY" "$FRAMEWORK"
  codesign --force --timestamp --options runtime --sign "$RADIOBAR_SIGNING_IDENTITY" "$APP"
  codesign -dv --verbose=2 "$APP" 2> "$STAGE/signature.txt"
  /usr/bin/grep -q '^Authority=Developer ID Application:' "$STAGE/signature.txt" || { echo 'A Developer ID Application certificate is required.' >&2; exit 1; }
  /usr/bin/grep -q '^Timestamp=' "$STAGE/signature.txt" || { echo 'A secure signing timestamp is required.' >&2; exit 1; }
else
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
/usr/bin/xattr -lr "$APP" > "$STAGE/app-attributes.txt"
/usr/bin/ditto -c -k --norsrc --keepParent "$APP" "$ARCHIVE"
/usr/bin/xattr -l "$ARCHIVE" > "$STAGE/archive-attributes.txt"
if /usr/bin/grep -F 'com.apple.quarantine:' "$STAGE/app-attributes.txt" "$STAGE/archive-attributes.txt" >/dev/null; then
  echo 'Unexpected quarantine metadata in the staged app or archive; previous package kept.' >&2
  exit 1
fi
/bin/mv -f "$ARCHIVE" "$DESTINATION"
echo "Built: $PWD/$DESTINATION"
