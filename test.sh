#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/ModuleCache
./Tools/Tests/test-builtin-streams.sh
FLAGS=(-D RADIOBAR_TESTING -swift-version 5 -target arm64-apple-macosx14.0 -module-cache-path "$PWD/build/ModuleCache" -parse-as-library)
xcrun swiftc "${FLAGS[@]}" Sources/RadioBar/AppLanguage.swift Sources/RadioBar/RadioDiagnostics.swift Sources/RadioBar/BuiltinStreams.swift Sources/RadioBar/StationCatalog.swift Sources/RadioBar/StreamResolver.swift Tests/ResolverTests.swift -o build/ResolverTests
./build/ResolverTests
xcrun swiftc "${FLAGS[@]}" Sources/RadioBar/AppLanguage.swift Sources/RadioBar/AppSettings.swift Sources/RadioBar/StationSharing.swift Sources/RadioBar/StationSync.swift Sources/RadioBar/StationSyncDirectory.swift Sources/RadioBar/StationConfigurationTransaction.swift Sources/RadioBar/MacStationSync.swift Sources/RadioBar/RadioDiagnostics.swift Sources/RadioBar/BuiltinStreams.swift Sources/RadioBar/StationCatalog.swift Sources/RadioBar/StreamResolver.swift Sources/RadioBar/PlaybackPreferences.swift Sources/RadioBar/SleepTimer.swift Sources/RadioBar/AudioPlayback.swift Sources/RadioBar/RadioPlayer.swift Sources/RadioBar/ChannelReordering.swift Tests/SettingsTests.swift -o build/SettingsTests
./build/SettingsTests
xcrun swiftc "${FLAGS[@]}" Sources/RadioBar/AppLanguage.swift Sources/RadioBar/RadioDiagnostics.swift Sources/RadioBar/BuiltinStreams.swift Sources/RadioBar/StationCatalog.swift Sources/RadioBar/StreamResolver.swift Sources/RadioBar/PlaybackPreferences.swift Sources/RadioBar/SleepTimer.swift Sources/RadioBar/AudioPlayback.swift Sources/RadioBar/RadioPlayer.swift Tests/SleepTimerTests.swift -o build/SleepTimerTests
./build/SleepTimerTests
xcrun swiftc "${FLAGS[@]}" Sources/RadioBar/SingleInstanceLock.swift Tests/SingleInstanceTests.swift -o build/SingleInstanceTests
./build/SingleInstanceTests
xcrun swiftc "${FLAGS[@]}" Sources/RadioBar/AppLanguage.swift Sources/RadioBar/AppSettings.swift Sources/RadioBar/StationSharing.swift Sources/RadioBar/StationSync.swift Sources/RadioBar/StationSyncDirectory.swift Sources/RadioBar/StationConfigurationTransaction.swift Sources/RadioBar/MacStationSync.swift Sources/RadioBar/RadioDiagnostics.swift Sources/RadioBar/BuiltinStreams.swift Sources/RadioBar/StationCatalog.swift Sources/RadioBar/StreamResolver.swift Sources/RadioBar/PlaybackPreferences.swift Sources/RadioBar/SleepTimer.swift Sources/RadioBar/AudioPlayback.swift Sources/RadioBar/RadioPlayer.swift Sources/RadioBar/MenuBarSignal.swift Tests/MenuBarSignalTests.swift -o build/MenuBarSignalTests
./build/MenuBarSignalTests
xcrun swiftc "${FLAGS[@]}" Sources/RadioBar/AppLanguage.swift Sources/RadioBar/RadioDiagnostics.swift Sources/RadioBar/BuiltinStreams.swift Sources/RadioBar/StationCatalog.swift Sources/RadioBar/StreamResolver.swift Sources/RadioBar/PlaybackPreferences.swift Sources/RadioBar/SleepTimer.swift Sources/RadioBar/AudioPlayback.swift Sources/RadioBar/RadioPlayer.swift Tests/DiagnosticsTests.swift -o build/DiagnosticsTests
./build/DiagnosticsTests
./Tools/Tests/test-station-sync.sh
./Tools/Tests/test-mac-station-sync.sh
./Tools/Tests/test-audio-transitions.sh
./Tools/Tests/test-native-channel-drops.sh
./Tools/Tests/test-dock-visibility.sh
if [[ "${1:-}" == "--network" || "${1:-}" == "--network-fixed" || "${1:-}" == "--network-ufo" || "${1:-}" == "--network-guangdong" ]]; then
  ./Tools/Tests/test-playback.sh "$1"
fi
