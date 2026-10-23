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
  "${SOURCES[@]}" Tools/NativeAudioTransitionProbe.swift -o build/NativeAudioTransitionProbe
./build/NativeAudioTransitionProbe > build/native-audio-transitions.log 2>&1
cat build/native-audio-transitions.log
rg -q '^PASS: real native AVPlayer' build/native-audio-transitions.log
