#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
source Tools/sparkle-config.sh
[[ -f build/updates/appcast.xml ]] || { echo 'Run ./build.sh and ./Tools/sign-release.sh first.' >&2; exit 1; }
STAGE=$(mktemp -d /private/tmp/RadioBar-update-tests.XXXXXX)
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Resources/Info.plist)
server_pid=''
cleanup() {
  if [[ -n "$server_pid" ]]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi
  rm -rf "$STAGE"
}
trap cleanup EXIT
python3 Tools/serve-update-fixtures.py build/updates/appcast.xml "$STAGE/port" &
server_pid=$!
for ((i=0;i<100;i++)); do
  [[ -f "$STAGE/port" ]] && break
  kill -0 "$server_pid" 2>/dev/null || { echo 'Fixture server failed' >&2; exit 1; }
  sleep 0.05
done
port=$(cat "$STAGE/port")
APP="$STAGE/UpdateProbe.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Frameworks" "$APP/Contents/Resources"
./Tools/prepare-builtin-streams.sh "$APP/Contents/Resources/builtin-streams.json"
cp -X Sources/RadioBar/Resources/stations.default.json "$APP/Contents/Resources/stations.default.json"
cp -X Resources/RadioBar.icns "$APP/Contents/Resources/RadioBar.icns"
xcrun swiftc -swift-version 5 -parse-as-library -module-cache-path "$PWD/build/ModuleCache" \
  -F "$SPARKLE_ROOT" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
  Sources/RadioBar/AppLanguage.swift Sources/RadioBar/BuiltinStreams.swift Sources/RadioBar/StationCatalog.swift Sources/RadioBar/StreamResolver.swift \
  Sources/RadioBar/RadioDiagnostics.swift \
  Sources/RadioBar/AppUpdater.swift Tests/SparkleProbe.swift -o "$APP/Contents/MacOS/RadioBar"
/usr/bin/ditto --norsrc "$SPARKLE_ROOT/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
cp Resources/Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier local.victor.RadioBar.UpdateProbe' "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Add :NSAppTransportSecurity:NSAllowsLocalNetworking bool true' "$APP/Contents/Info.plist"
# Real signed feed: current build has no update, a lower build discovers the release.
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/RadioBar" controller
"$APP/Contents/MacOS/RadioBar" "http://127.0.0.1:$port/appcast.xml" no-update "$build_number"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((build_number - 1))" "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
"$APP/Contents/MacOS/RadioBar" "http://127.0.0.1:$port/appcast.xml" found "$build_number"
"$APP/Contents/MacOS/RadioBar" "http://127.0.0.1:$port/tampered.xml" rejected "$build_number"
"$APP/Contents/MacOS/RadioBar" "http://127.0.0.1:$port/tampered-notes.xml" rejected "$build_number"
mkdir -p build/update-previews
for language in zh-Hans zh-Hant en; do
  case "$language" in
    zh-Hans) heading='本次更新' ;;
    zh-Hant) heading='本次更新' ;;
    en) heading="What's New" ;;
  esac
  "$APP/Contents/MacOS/RadioBar" "http://127.0.0.1:$port/appcast-$language.xml" found "$build_number" "$heading"
  for appearance in light dark; do
    "$APP/Contents/MacOS/RadioBar" "http://127.0.0.1:$port/appcast-$language.xml" preview "$build_number" "$heading" "$PWD/build/update-previews/$language-$appearance.png" "$appearance"
  done
done
# Archive tampering must fail independent public-key verification.
cp build/updates/RadioBar-macOS-arm64.zip "$STAGE/tampered.zip"
printf 'tampered' >> "$STAGE/tampered.zip"
if ./build/VerifyUpdate Resources/Info.plist build/updates/appcast.xml "$STAGE/tampered.zip" \
  "https://github.com/GiaoGiaoCat/RadioBar/releases/download/v$version/RadioBar-macOS-arm64.zip" > "$STAGE/rejection.log" 2>&1; then
  echo 'FAIL: tampered archive accepted' >&2
  exit 1
fi
echo 'PASS: tampered archive rejected'
python3 Tests/ReleaseOrderTests.py
