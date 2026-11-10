#!/usr/bin/env bash
# Copy the behavior spec across the wall and make the clean-room copy read-only.
# Equivalent to, from lab/:
#   cp handoff/SPEC.md ../clean/SPEC.md && chmod a-w ../clean/SPEC.md
# Runs the leak grep first and refuses to copy when it matches.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC="${1:-$ROOT/lab/handoff/SPEC.md}"
DEST="${2:-$ROOT/clean/SPEC.md}"

"$ROOT/scripts/leak-check.sh" "$SRC"

mkdir -p "$(dirname "$DEST")"
if [[ -e "$DEST" ]]; then
  chmod u+w "$DEST" || true
fi
cp "$SRC" "$DEST"
chmod a-w "$DEST"
echo "copied $SRC -> $DEST (read-only)"
