#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/ModuleCache
TEST_STAGE="$(mktemp -d /private/tmp/RadioBar-builtin-tests.XXXXXX)"
trap 'rm -rf "$TEST_STAGE"' EXIT
FLAGS=(-swift-version 5 -parse-as-library -module-cache-path "$PWD/build/ModuleCache")
xcrun swiftc "${FLAGS[@]}" Sources/RadioBar/BuiltinStreams.swift Tools/PrepareBuiltinStreams.swift -o "$TEST_STAGE/PrepareBuiltinStreams"
xcrun swiftc "${FLAGS[@]}" Sources/RadioBar/BuiltinStreams.swift Tests/BuiltinStreamsTests.swift -o "$TEST_STAGE/BuiltinStreamsTests"
"$TEST_STAGE/BuiltinStreamsTests" "$TEST_STAGE/PrepareBuiltinStreams"
