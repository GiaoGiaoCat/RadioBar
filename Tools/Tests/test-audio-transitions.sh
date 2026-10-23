#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/ModuleCache
xcrun swiftc -D RADIOBAR_TESTING -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path "$PWD/build/ModuleCache" -parse-as-library \
  Sources/RadioBar/AppLanguage.swift Sources/RadioBar/RadioDiagnostics.swift \
  Sources/RadioBar/BuiltinStreams.swift Sources/RadioBar/StationCatalog.swift Sources/RadioBar/StreamResolver.swift \
  Sources/RadioBar/PlaybackPreferences.swift Sources/RadioBar/SleepTimer.swift \
  Sources/RadioBar/AudioPlayback.swift Sources/RadioBar/RadioPlayer.swift \
  Tests/AudioTransitionTests.swift -o build/AudioTransitionTests
./build/AudioTransitionTests
