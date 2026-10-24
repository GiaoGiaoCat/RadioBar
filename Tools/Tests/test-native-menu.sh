#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/ModuleCache
rm -f build/native-menu-result.txt
python3 Tools/PrepareMenuPreview.py build/NativeMenuTests.swift --native-tests
SOURCES=()
for source in Sources/RadioBar/*.swift; do
  if [[ "$source" != "Sources/RadioBar/RadioBarApp.swift" && "$source" != "Sources/RadioBar/RadioPlayer.swift" ]]; then SOURCES+=("$source"); fi
done
xcrun swiftc -D RADIOBAR_TESTING -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path "$PWD/build/ModuleCache" -parse-as-library \
  "${SOURCES[@]}" build/PreviewRadioPlayer.swift build/NativeMenuTests.swift -o build/NativeMenuTests
./build/NativeMenuTests
