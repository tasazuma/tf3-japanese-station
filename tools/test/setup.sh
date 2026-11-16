#!/bin/bash
# Extract the vanilla scripts the offline harness needs from your own TF3 install.
# Game files are not part of this repository; they are copied to tools/test/.vanilla (git-ignored).
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
GAME="${TF3_GAME:-$HOME/Library/Application Support/Steam/steamapps/common/Transport Fever 3}"
ZIP="$GAME/base/content/scripts.zip"
[ -f "$ZIP" ] || { echo "not found: $ZIP (set TF3_GAME to your Transport Fever 3 install folder)" >&2; exit 1; }
OUT="$HERE/.vanilla"
rm -rf "$OUT"
mkdir -p "$OUT/lib"
# the game zips are not readable by every unzip tool; Python's zipfile handles them
python3 -c 'import sys, zipfile; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])' "$ZIP" "$OUT/base"
for f in vec3 vec4 mat4; do
  python3 "$HERE/strip_tl.py" "$OUT/base/scripts/$f.tl" > "$OUT/lib/$f.lua"
done
echo "ok: $OUT"
