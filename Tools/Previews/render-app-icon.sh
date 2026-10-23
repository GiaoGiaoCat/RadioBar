#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p build/ModuleCache
xcrun swiftc -swift-version 5 -target arm64-apple-macosx14.0 \
  -module-cache-path "$PWD/build/ModuleCache" Tools/RenderAppIcon.swift -o build/AppIconPreview
STAGE="$(mktemp -d /private/tmp/RadioBar-icon-preview.XXXXXX)"
trap 'rm -rf "$STAGE"' EXIT
/usr/bin/ditto -x -k build/RadioBar-macOS-arm64.zip "$STAGE"
codesign --verify --strict "$STAGE/RadioBar.app"
./build/AppIconPreview "$STAGE/RadioBar.app" "${1:-build/app-icon-previews}"
