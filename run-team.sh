#!/usr/bin/env bash
# One feature: analyst -> spec writer -> rebuilder inside rea-clean -> verifier.
# Usage: ./run-team.sh target/YourApp.app "how search ranks results"
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo 'Usage: ./run-team.sh target/YourApp.app "how search ranks results"' >&2
  exit 1
fi
if ! command -v claude >/dev/null 2>&1; then
  echo "claude is not on PATH. Install the Claude Code CLI on the lab side (WSL, not inside rea-clean)." >&2
  exit 1
fi
if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not on PATH" >&2
  exit 1
fi
if ! docker inspect -f '{{.State.Running}}' rea-clean 2>/dev/null | grep -qx true; then
  echo "container rea-clean is not running. From the repo root: docker compose up -d --build" >&2
  exit 1
fi
TARGET="$1"; FEATURE="$2"; MAX_ROUNDS=3
cd "$(dirname "$0")/lab"

claude -p "$(printf 'Use the analyst agent on %s. Feature: %s' "$TARGET" "$FEATURE")"
claude -p "Use the spec-writer agent to write handoff/SPEC.md from analysis/evidence.md"

for round in $(seq 1 "$MAX_ROUNDS"); do
  if grep -nEi '0x[0-9a-f]{5,}|sub_[0-9a-f]+|var_[0-9a-f]+|FUN_[0-9a-f]+' handoff/SPEC.md; then
    echo "spec leaks decompiled names, stopping"; exit 1
  fi

  docker cp handoff/SPEC.md rea-clean:/work/SPEC.md
  docker exec rea-clean claude -p "Use the rebuilder agent on /work/SPEC.md"
  rm -rf rebuild && docker cp rea-clean:/work/src ./rebuild

  claude -p "Use the verifier agent."
  tail -n 1 report.md
  grep -q 'RESULT wrong=0 crash=0' report.md && { echo "parity reached in round $round"; exit 0; }

  claude -p "Use the spec-writer agent to add every wrong or crash divergence in report.md as a case under Test Cases in handoff/SPEC.md"
done
echo "no parity after $MAX_ROUNDS rounds, read report.md"; exit 2
