#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 1 ]]; then
  echo 'Usage: Tools/prepare-builtin-streams.sh OUTPUT_JSON' >&2
  exit 2
fi
PREPARE_STAGE="$(mktemp -d /private/tmp/RadioBar-stream-input.XXXXXX)"
trap 'rm -rf "$PREPARE_STAGE"' EXIT
umask 077
xcrun swiftc -swift-version 5 -parse-as-library \
  -module-cache-path "$PREPARE_STAGE/ModuleCache" \
  Sources/RadioBar/BuiltinStreams.swift Tools/PrepareBuiltinStreams.swift \
  -o "$PREPARE_STAGE/PrepareBuiltinStreams"
"$PREPARE_STAGE/PrepareBuiltinStreams" "$PWD/private/builtin-streams.json" "$1"
