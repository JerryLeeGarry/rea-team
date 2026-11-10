#!/usr/bin/env bash
# Fail if handoff/SPEC.md still contains addresses or decompiled names.
# Wraps:
#   grep -nEi '0x[0-9a-f]{5,}|sub_[0-9a-f]+|var_[0-9a-f]+|FUN_[0-9a-f]+' handoff/SPEC.md
# No grep output means nothing leaked.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SPEC="${1:-$ROOT/lab/handoff/SPEC.md}"

if [[ ! -f "$SPEC" || ! -s "$SPEC" ]]; then
  echo "SPEC is missing or empty: $SPEC" >&2
  exit 1
fi

if grep -nEi '0x[0-9a-f]{5,}|sub_[0-9a-f]+|var_[0-9a-f]+|FUN_[0-9a-f]+' "$SPEC"; then
  echo "spec leaks decompiled names, stopping" >&2
  exit 1
fi

echo "leak check passed (no decompiled names): $SPEC"
