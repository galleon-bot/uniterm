#!/usr/bin/env bash
#
# Runs the UI tests, given as an xcodebuild command: run-ui-tests.sh xcodebuild ... test
#
# UI tests drive the app through Launch Services and the Accessibility API. Without a GUI session
# the run cannot start. Without Accessibility permission it fails while enabling automation. This
# script names those causes instead of leaving a bare xcodebuild failure.

set -euo pipefail

if ! swift -e 'import CoreGraphics; exit(CGSessionCopyCurrentDictionary() == nil ? 1 : 0)' 2>/dev/null; then
  echo "error: UI tests need a logged-in GUI session, and this shell has none." >&2
  echo "Run make test-app from Terminal on the desktop." >&2
  exit 1
fi

log="$(mktemp "${TMPDIR:-/tmp}/uniterm-ui-tests.XXXXXX")"
trap 'rm -f "$log"' EXIT

if "$@" 2>&1 | tee "$log"; then
  exit 0
fi

if grep -qiE 'automation mode|not authorized|failed to initialize for UI testing|timed out while loading accessibility' "$log"; then
  echo "error: the UI tests could not drive the app. Grant Accessibility permission to Xcode and to the" >&2
  echo "terminal running make, in System Settings > Privacy & Security > Accessibility. Then run again." >&2
fi
exit 1
