#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ $# != 2 || ! -f "$1" || ! "$2" =~ ^[0-9a-f]{64}$ ]]; then
  echo 'Usage: ./Tools/verify-notarized-release.sh <ZIP> <lowercase SHA-256>' >&2
  exit 2
fi
archive="$1"
expected_digest="$2"
actual_digest=$(shasum -a 256 "$archive" | awk '{print $1}')
[[ "$actual_digest" == "$expected_digest" ]] || { echo 'Archive SHA-256 does not match.' >&2; exit 1; }
stage=$(mktemp -d /private/tmp/RadioBar-release-check.XXXXXX)
trap 'rm -rf "$stage"' EXIT
ditto -x -k "$archive" "$stage"
app="$stage/RadioBar.app"
test -d "$app"
codesign --verify --deep --strict "$app"
codesign -dv --verbose=2 "$app" 2> "$stage/signature.txt"
grep -q '^Authority=Developer ID Application:' "$stage/signature.txt"
grep -q '^TeamIdentifier=8H54LK5X2H$' "$stage/signature.txt"
grep -q '^Timestamp=' "$stage/signature.txt"
grep -q 'flags=.*runtime' "$stage/signature.txt"
test "$(lipo -archs "$app/Contents/MacOS/RadioBar")" = arm64
python3 - "$app/Contents/Info.plist" Resources/Info.plist <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as f:
    actual = plistlib.load(f)
with open(sys.argv[2], 'rb') as f:
    expected = plistlib.load(f)
if actual != expected:
    raise SystemExit('App Info.plist does not match the tagged source.')
PY
xcrun stapler validate "$app"
spctl --assess --type execute --verbose=2 "$app"
echo 'PASS: ZIP hash, metadata, Developer ID, notarization and Gatekeeper'
