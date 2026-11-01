#!/usr/bin/env bash
#
# Fails when the app could run inside the App Sandbox. A sandboxed app cannot give the shell its
# user's home folder, so the terminal would break.
#
# The check reads the Xcode project and any entitlements file. A built app can be checked as well:
#   scripts/check-sandbox-off.sh path/to/uniterm.app

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT="$ROOT/uniterm.xcodeproj/project.pbxproj"
status=0

fail() {
  echo "error: $*" >&2
  status=1
}

settings="$(grep -E 'ENABLE_APP_SANDBOX' "$PROJECT" || true)"
[ -n "$settings" ] || fail "$PROJECT does not set ENABLE_APP_SANDBOX."
if printf '%s\n' "$settings" | grep -vq 'ENABLE_APP_SANDBOX = NO;'; then
  fail "ENABLE_APP_SANDBOX is not NO everywhere in $PROJECT."
fi

if grep -rq 'com.apple.security.app-sandbox' "$ROOT/App" 2>/dev/null; then
  fail "an entitlements file under App/ turns the App Sandbox on."
fi

if [ "$#" -ge 1 ]; then
  if codesign -d --entitlements - "$1" 2>/dev/null | grep -q 'com.apple.security.app-sandbox'; then
    fail "$1 carries the App Sandbox entitlement."
  fi
fi

if [ "$status" = "0" ]; then
  echo "The App Sandbox is off."
fi

exit "$status"
