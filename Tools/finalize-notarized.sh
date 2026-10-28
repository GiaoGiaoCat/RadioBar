#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# -ne 1 || ! -f "$1" ]]; then
  echo 'Usage: ./Tools/finalize-notarized.sh <submitted ZIP>' >&2
  exit 2
fi
input="$1"
mkdir -p build
stage="$(mktemp -d /private/tmp/RadioBar-notary.XXXXXX)"
output_stage="$(mktemp -d "$PWD/build/RadioBar-notary-package.XXXXXX")"
trap 'rm -rf "$stage" "$output_stage"' EXIT
ditto -x -k "$input" "$stage"
app="$stage/RadioBar.app"
test -d "$app"
codesign --verify --deep --strict "$app"
codesign -dv --verbose=2 "$app" 2> "$stage/signature.txt"
grep -q '^Authority=Developer ID Application:' "$stage/signature.txt"
grep -q '^Timestamp=' "$stage/signature.txt"
xcrun stapler staple "$app"
xcrun stapler validate "$app"
codesign --verify --deep --strict "$app"
ditto -c -k --keepParent "$app" "$output_stage/RadioBar-macOS-arm64.zip"
mkdir "$stage/verify"
ditto -x -k "$output_stage/RadioBar-macOS-arm64.zip" "$stage/verify"
codesign --verify --deep --strict "$stage/verify/RadioBar.app"
xcrun stapler validate "$stage/verify/RadioBar.app"
spctl --assess --type execute --verbose=2 "$stage/verify/RadioBar.app"
mv -f "$output_stage/RadioBar-macOS-arm64.zip" build/RadioBar-macOS-arm64.zip
echo "Built notarized archive: $PWD/build/RadioBar-macOS-arm64.zip"
