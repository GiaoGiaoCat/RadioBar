#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
case "${1:---network-fixed}" in
  --network|--network-fixed|--network-ufo|--network-guangdong) ;;
  *) echo 'Usage: test-playback.sh [--network-fixed|--network|--network-ufo|--network-guangdong]' >&2; exit 2 ;;
esac
mkdir -p build/ModuleCache
PROBE_STAGE="$(mktemp -d /private/tmp/RadioBar-probe.XXXXXX)"
trap 'rm -rf "$PROBE_STAGE"' EXIT
PROBE="$PROBE_STAGE/PlaybackProbe.app"
mkdir -p "$PROBE/Contents/MacOS" "$PROBE/Contents/Resources"
./Tools/prepare-builtin-streams.sh "$PROBE_STAGE/BuiltinStreams"
cp -X "$PROBE_STAGE/BuiltinStreams/builtin-streams.bin" "$PROBE/Contents/Resources/builtin-streams.bin"
cp -X Resources/Info.plist "$PROBE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable PlaybackProbe' "$PROBE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.victor.RadioBar.Probe' "$PROBE/Contents/Info.plist"
xcrun swiftc -D RADIOBAR_TESTING -D RADIOBAR_LIVE_STREAMS -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path "$PWD/build/ModuleCache" -parse-as-library \
  Sources/RadioBar/AppLanguage.swift Sources/RadioBar/RadioDiagnostics.swift \
  Sources/RadioBar/BuiltinStreams.swift Sources/RadioBar/StationCatalog.swift Sources/RadioBar/StreamResolver.swift \
  Sources/RadioBar/PlaybackPreferences.swift Sources/RadioBar/SleepTimer.swift \
  Sources/RadioBar/AudioPlayback.swift Sources/RadioBar/RadioPlayer.swift \
  "$PROBE_STAGE/BuiltinStreams/BuiltinStreamKey.swift" Tools/PlaybackProbe.swift -o "$PROBE/Contents/MacOS/PlaybackProbe"
codesign --force --sign - "$PROBE"
"$PROBE/Contents/MacOS/PlaybackProbe" "${1:---network-fixed}"
