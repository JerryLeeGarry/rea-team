#!/usr/bin/env bash
# Run the three clean-room wall checks inside rea-clean.
# Force ALLOW_NPM=0 for this run and require the image flag to be 0.
# It passes only when all three fail:
#   which rea
#   npx --no-install rea-agents --version
#   ls /lab /target 2>&1
set -euo pipefail
export ALLOW_NPM=0

CONTAINER="${REA_CLEAN_CONTAINER:-rea-clean}"
marker="__REA_WALL_EC__"
status=0

if ! command -v docker >/dev/null 2>&1; then
  echo "docker is not on PATH" >&2
  exit 1
fi

if ! running="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" || [[ "$running" != 'true' ]]; then
  echo "container ${CONTAINER} is not running. From the repo root: docker compose up -d --build" >&2
  exit 1
fi

if ! docker exec -e ALLOW_NPM=0 "$CONTAINER" true; then
  echo "cannot exec into ${CONTAINER}" >&2
  exit 1
fi

expect_fail() {
  local label="$1"
  local cmd="$2"
  local out ec

  if ! out="$(docker exec -e ALLOW_NPM=0 "$CONTAINER" sh -c "${cmd}; echo ${marker}:\$?" 2>&1)"; then
    echo "wall check inconclusive: ${label} (docker exec failed)" >&2
    printf '%s\n' "$out" >&2
    status=1
    return
  fi
  ec="$(printf '%s\n' "$out" | sed -n "s/^${marker}://p" | tail -n 1)"
  if [[ ! "$ec" =~ ^(0|[1-9][0-9]{0,2})$ ]] || (( ec > 255 )); then
    echo "wall check inconclusive: ${label} (missing or invalid exit marker from ${CONTAINER})" >&2
    printf '%s\n' "$out" >&2
    status=1
    return
  fi
  if [[ "$ec" == "0" ]]; then
    echo "WALL OPEN: ${label} succeeded inside ${CONTAINER}. Expected failure." >&2
    printf '%s\n' "$out" >&2
    status=1
    return
  fi
  echo "ok: ${label} failed inside ${CONTAINER} (exit ${ec})"
}

expect_fail "which rea" "which rea"
expect_fail "npx --no-install rea-agents --version" "npx --no-install rea-agents --version"
expect_fail "ls /lab /target" "ls /lab /target 2>&1"

if ! allow="$(docker exec -e ALLOW_NPM=0 "$CONTAINER" cat /etc/rea-clean/allow-npm 2>/dev/null)" || [[ "$allow" != "0" ]]; then
  echo "WALL OPEN: expected ALLOW_NPM=0, got ${allow:-unset}. After dependency install, rebuild with ALLOW_NPM=0. See README." >&2
  status=1
fi

exit "$status"
