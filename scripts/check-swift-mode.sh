#!/usr/bin/env bash
#
# Fails when the package and the app target use different Swift language modes, or when the app
# target does not check concurrency strictly.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE="$ROOT/Packages/UnitermKit/Package.swift"
PROJECT="$ROOT/uniterm.xcodeproj/project.pbxproj"

die() {
  echo "error: $*" >&2
  exit 1
}

package_modes="$(grep -Eo 'swiftLanguageModes: \[[^]]*\]' "$PACKAGE" | grep -Eo '\.v[0-9]+' | sort -u || true)"
[ -n "$package_modes" ] || die "$PACKAGE does not set swiftLanguageModes."
[ "$(printf '%s\n' "$package_modes" | wc -l)" -eq 1 ] || die "$PACKAGE sets more than one language mode: $package_modes"
package_major="${package_modes#.v}"

app_versions="$(grep -Eo 'SWIFT_VERSION = [0-9.]+' "$PROJECT" | awk '{ print $3 }' | sort -u || true)"
[ -n "$app_versions" ] || die "$PROJECT does not set SWIFT_VERSION."
[ "$(printf '%s\n' "$app_versions" | wc -l)" -eq 1 ] || die "$PROJECT sets more than one SWIFT_VERSION: $app_versions"
app_major="${app_versions%%.*}"

if [ "$package_major" != "$app_major" ]; then
  die "the package uses Swift language mode $package_major, but the app uses SWIFT_VERSION $app_versions."
fi

if ! grep -q 'SWIFT_STRICT_CONCURRENCY = complete' "$PROJECT"; then
  die "$PROJECT does not set SWIFT_STRICT_CONCURRENCY = complete."
fi

echo "Swift language mode $package_major in the package and the app."
