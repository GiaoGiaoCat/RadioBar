#!/bin/bash
# One-time setup from the maintainer's Mac. Requires GitHub CLI authenticated for this repository.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v gh >/dev/null || { echo 'Install GitHub CLI and run gh auth login first.' >&2; exit 1; }
source Tools/sparkle-config.sh
[[ -x "$SPARKLE_ROOT/bin/generate_keys" ]] || ./Tools/fetch-sparkle.sh
umask 077
key_file=$(mktemp /private/tmp/RadioBar-update-key.XXXXXX)
trap 'rm -f "$key_file"' EXIT
# Export only this app's dedicated key. Never print it or place it in the repository.
"$SPARKLE_ROOT/bin/generate_keys" --account local.victor.RadioBar -x "$key_file"
gh secret set SPARKLE_PRIVATE_KEY --repo GiaoGiaoCat/RadioBar < "$key_file"
echo 'Configured SPARKLE_PRIVATE_KEY for GiaoGiaoCat/RadioBar.'
