#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Tools/sparkle-config.sh
[[ -x "$SPARKLE_ROOT/bin/generate_appcast" ]] || ./Tools/fetch-sparkle.sh
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
repo=${GITHUB_REPOSITORY:-GiaoGiaoCat/RadioBar}
url="https://github.com/$repo/releases/download/v$version/"
feed="$PWD/build/updates"
rm -rf "$feed"
mkdir -p "$feed"
cp build/RadioBar-macOS-arm64.zip "$feed/"
arguments=(--download-url-prefix "$url" --link "https://github.com/$repo" --maximum-deltas 0)
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  # Supply the Actions secret over stdin, never as an argument or a file.
  printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_ROOT/bin/generate_appcast" --ed-key-file - "${arguments[@]}" "$feed"
else
  "$SPARKLE_ROOT/bin/generate_appcast" --account local.victor.RadioBar "${arguments[@]}" "$feed"
fi
SOURCES=()
for source in Sources/RadioBar/*.swift; do
  [[ "$source" == "Sources/RadioBar/RadioBarApp.swift" ]] || SOURCES+=("$source")
done
xcrun swiftc -D RADIOBAR_TESTING -swift-version 5 -parse-as-library -module-cache-path "$PWD/build/ModuleCache" \
  "${SOURCES[@]}" Tools/PrepareUpdateNotes.swift -o build/PrepareUpdateNotes
./build/PrepareUpdateNotes "$feed"
xcrun swiftc -parse-as-library -module-cache-path "$PWD/build/ModuleCache" Tools/VerifyUpdate.swift -o build/VerifyUpdate
for appcast in "$feed"/appcast*.xml; do
  if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
    printf '%s' "$SPARKLE_PRIVATE_KEY" | "$SPARKLE_ROOT/bin/sign_update" --ed-key-file - "$appcast"
  else
    "$SPARKLE_ROOT/bin/sign_update" --account local.victor.RadioBar "$appcast"
  fi
  ./build/VerifyUpdate Resources/Info.plist "$appcast" "$feed/RadioBar-macOS-arm64.zip" "${url}RadioBar-macOS-arm64.zip"
done
