#!/bin/bash
# Symlink each mod folder in this repo into the TF3 staging_area (idempotent).
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
if [ -z "${TF3_STAGING:-}" ]; then
  # macOS Steam: userdata/<your Steam id>/3493540 (TF3 app id)/local/staging_area
  for d in "$HOME/Library/Application Support/Steam/userdata"/*/3493540; do
    [ -d "$d" ] && TF3_STAGING="$d/local/staging_area" && break
  done
fi
STAGING="${TF3_STAGING:?TF3 staging_area not found; set TF3_STAGING}"
mkdir -p "$STAGING"
for mod in "$REPO"/jpst_*/; do
  name="$(basename "$mod")"
  ln -sfn "${mod%/}" "$STAGING/$name"
  echo "linked: $STAGING/$name -> ${mod%/}"
done
