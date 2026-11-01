#!/usr/bin/env bash
#
# Collects the license notices that ship in the app, into Licenses/ at the repo root.
#
# Usage: scripts/collect-licenses.sh
#
# The notices come from three places:
#   - Ghostty's own LICENSE, its bundled font notices, and its vendored nerd-fonts notice. They are
#     read from the pinned source tarball in the Ghostty cache.
#   - Every Zig package that the pinned Ghostty build fetched, from the kept package cache. These
#     are the libraries that end up linked or bundled. A package that carries no license file is
#     named in Licenses/README.txt.
#   - Catppuccin, whose palette uniterm uses.
#
# Rerun it when ghostty.pin changes, and commit the result. The Xcode build copies Licenses/ into
# Contents/Resources/Licenses.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PIN_FILE="${GHOSTTY_PIN_FILE:-$ROOT/ghostty.pin}"
CACHE="${GHOSTTY_CACHE_DIR:-$ROOT/.cache/ghostty}"
OUT="${LICENSES_DIR:-$ROOT/Licenses}"

die() {
  echo "error: $*" >&2
  exit 1
}

# shellcheck disable=SC1090
. "$PIN_FILE"

tarball="$CACHE/dl/$GHOSTTY_COMMIT.tar.gz"
[ -f "$tarball" ] || die "the Ghostty source is not cached. Run make build first."
[ -d "$CACHE/zig-global/p" ] || die "the Zig package cache is missing. Run make build first."

work="$(mktemp -d "${TMPDIR:-/tmp}/uniterm-licenses.XXXXXX")"
trap 'rm -rf "$work"' EXIT

tar -xzf "$tarball" -C "$work" --strip-components=1 \
  --exclude='.gitmodules' --exclude='.gitattributes' --exclude='.gitignore' --exclude='.git'

python3 -I - "$work" "$CACHE/zig-global/p" "$OUT" "$GHOSTTY_TAG" <<'PY'
import json
import os
import re
import shutil
import sys

source, packages, out, tag = sys.argv[1:5]

LICENSE_NAME = re.compile(r"^(licen[sc]e|copying|copyright|notice|unlicense|ofl)([-_.].*)?$", re.I)

shutil.rmtree(out, ignore_errors=True)
os.makedirs(out)


def copy(src, dst):
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    shutil.copyfile(src, dst)


def license_files(root, depth=2):
    found = []
    for current, dirs, files in os.walk(root):
        level = current[len(root):].count(os.sep)
        if level >= depth:
            dirs[:] = []
        for name in sorted(files):
            if LICENSE_NAME.match(name):
                found.append(os.path.join(current, name))
    return sorted(found)


copy(os.path.join(source, "LICENSE"), os.path.join(out, "Ghostty", "LICENSE"))
copy(
    os.path.join(source, "vendor", "nerd-fonts", "LICENSE"),
    os.path.join(out, "Ghostty", "vendor-nerd-fonts-LICENSE"),
)

fonts = os.path.join(source, "src", "font", "res")
for name in sorted(os.listdir(fonts)):
    if name.endswith(".txt"):
        copy(os.path.join(fonts, name), os.path.join(out, "Ghostty", "fonts", name))

names = {}
with open(os.path.join(source, "build.zig.zon.json")) as handle:
    for key, value in json.load(handle).items():
        names[key] = value["name"]

without_license = []
for entry in sorted(os.listdir(packages)):
    root = os.path.join(packages, entry)
    if not os.path.isdir(root):
        continue

    name = names.get(entry)
    if name is None:
        match = re.match(r"^(.*?-\d+\.\d+\.\d+)-", entry)
        name = match.group(1) if match else entry

    files = license_files(root)
    if not files:
        without_license.append(name)
        continue

    for path in files:
        relative = os.path.relpath(path, root).replace(os.sep, "__")
        copy(path, os.path.join(out, "ghostty-dependencies", name, relative))

catppuccin = """MIT License

Copyright (c) 2021 Catppuccin

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""
os.makedirs(os.path.join(out, "Catppuccin"))
with open(os.path.join(out, "Catppuccin", "LICENSE"), "w") as handle:
    handle.write(catppuccin)

lines = [
    "License notices for the software that uniterm ships.",
    "",
    "Ghostty/                  Ghostty %s and its bundled font notices" % tag,
    "ghostty-dependencies/     the libraries that Ghostty's build fetched, one folder each",
    "Catppuccin/               the Catppuccin color palette",
    "",
]
if without_license:
    lines.append("These packages carry no license file in the fetched source. See their upstream projects:")
    lines.extend("  " + name for name in sorted(set(without_license)))
    lines.append("")

with open(os.path.join(out, "README.txt"), "w") as handle:
    handle.write("\n".join(lines))
PY

echo "Licenses written to $OUT"
