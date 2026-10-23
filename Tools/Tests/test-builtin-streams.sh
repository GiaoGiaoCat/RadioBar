#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/ModuleCache
TEST_STAGE="$(mktemp -d /private/tmp/RadioBar-builtin-tests.XXXXXX)"
trap 'rm -rf "$TEST_STAGE"' EXIT
FLAGS=(-swift-version 5 -parse-as-library -module-cache-path "$PWD/build/ModuleCache")
xcrun swiftc -D RADIOBAR_STREAM_TOOL "${FLAGS[@]}" Sources/RadioBar/BuiltinStreams.swift Tools/PrepareBuiltinStreams.swift -o "$TEST_STAGE/PrepareBuiltinStreams"
xcrun swiftc -D RADIOBAR_STREAM_TOOL "${FLAGS[@]}" Sources/RadioBar/BuiltinStreams.swift Tests/BuiltinStreamsTests.swift -o "$TEST_STAGE/BuiltinStreamsTests"
"$TEST_STAGE/BuiltinStreamsTests" "$TEST_STAGE/PrepareBuiltinStreams" "$TEST_STAGE"
KISS='https://fixture.invalid/kiss.m3u8?token=FAKE%2Bvalue&x=a+b&x=%2F&expires=1'
CNR='https://fixture.invalid/cnr.m3u8?empty=&encoded=%26%3D'
APP="$TEST_STAGE/Probe.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleExecutable Probe' "$APP/Contents/Info.plist"
for generation in Generated Swapped; do
  xcrun swiftc "${FLAGS[@]}" Sources/RadioBar/BuiltinStreams.swift "$TEST_STAGE/$generation/BuiltinStreamKey.swift" \
    Tests/BuiltinStreamsBundleProbe.swift -o "$APP/Contents/MacOS/Probe"
  cp "$TEST_STAGE/$generation/builtin-streams.bin" "$APP/Contents/Resources/builtin-streams.bin"
  if [[ "$generation" = Generated ]]; then
    "$APP/Contents/MacOS/Probe" "$KISS" "$CNR"
    # A different generation's resource cannot be opened with the first key.
    cp "$TEST_STAGE/Swapped/builtin-streams.bin" "$APP/Contents/Resources/builtin-streams.bin"
    "$APP/Contents/MacOS/Probe" --empty
  else
    "$APP/Contents/MacOS/Probe" "$CNR" "$KISS"
  fi
done
printf 'corrupt' > "$APP/Contents/Resources/builtin-streams.bin"
"$APP/Contents/MacOS/Probe" --empty
rm "$APP/Contents/Resources/builtin-streams.bin"
# Even an old plaintext resource cannot enable a fallback.
cp "$TEST_STAGE/input.json" "$APP/Contents/Resources/builtin-streams.json"
"$APP/Contents/MacOS/Probe" --empty
