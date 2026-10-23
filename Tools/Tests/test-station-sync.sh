#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/ModuleCache
SOURCES=(Sources/RadioBar/AppLanguage.swift Sources/RadioBar/RadioDiagnostics.swift
  Sources/RadioBar/BuiltinStreams.swift Sources/RadioBar/StationCatalog.swift Sources/RadioBar/StreamResolver.swift
  Sources/RadioBar/StationSharing.swift Sources/RadioBar/StationSync.swift
  Sources/RadioBar/StationConfigurationTransaction.swift Sources/RadioBar/StationSyncDirectory.swift)
case "${1:-}" in
  --typecheck-ios)
    for SDK in iphoneos iphonesimulator; do
      TARGET=arm64-apple-ios17.0
      if [[ "$SDK" == iphonesimulator ]]; then TARGET+=-simulator; fi
      xcrun --sdk "$SDK" swiftc -swift-version 5 -target "$TARGET" -sdk "$(xcrun --sdk "$SDK" --show-sdk-path)" \
        -module-cache-path "$PWD/build/ModuleCache" -parse-as-library -typecheck "${SOURCES[@]}"
    done
    ;;
  '')
    xcrun swiftc -D RADIOBAR_TESTING -swift-version 5 -target arm64-apple-macosx14.0 \
      -module-cache-path "$PWD/build/ModuleCache" -parse-as-library "${SOURCES[@]}" Tests/StationSyncTests.swift -o build/StationSyncTests
    ./build/StationSyncTests
    ;;
  *) echo 'Usage: test-station-sync.sh [--typecheck-ios]' >&2; exit 2 ;;
esac
