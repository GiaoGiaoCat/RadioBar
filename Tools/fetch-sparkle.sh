#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source Tools/sparkle-config.sh
mkdir -p build
archive="$PWD/build/Sparkle-$SPARKLE_VERSION.tar.xz"
verify_archive() { [[ "$(shasum -a 256 "$archive" | cut -d ' ' -f 1)" = "$SPARKLE_SHA256" ]]; }
if [[ ! -f "$archive" ]] || ! verify_archive; then
  download=$(mktemp "$PWD/build/Sparkle-download.XXXXXX")
  trap 'rm -f "$download"' EXIT
  curl --fail --location --retry 3 --proto '=https' --proto-redir '=https' \
    "https://github.com/sparkle-project/Sparkle/releases/download/$SPARKLE_VERSION/Sparkle-$SPARKLE_VERSION.tar.xz" -o "$download"
  [[ "$(shasum -a 256 "$download" | cut -d ' ' -f 1)" = "$SPARKLE_SHA256" ]] || { echo 'Sparkle checksum mismatch' >&2; exit 1; }
  mv "$download" "$archive"
fi
# Always extract from the verified archive, rather than trusting an old extracted cache.
rm -rf "$SPARKLE_ROOT"
mkdir -p "$SPARKLE_ROOT"
tar -xJf "$archive" -C "$SPARKLE_ROOT"
