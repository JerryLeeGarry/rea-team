#!/bin/bash
# Start the clean room: refuse a mount that exposes the lab, then apply the
# outbound allowlist. docker compose keeps this process as PID 1.
set -euo pipefail

forbidden=(
  /lab
  /target
  /work/lab
  /work/analysis
  /work/handoff
  /work/run-team.sh
  /workspace/lab
  /workspaces/lab
)
for path in "${forbidden[@]}"; do
  if [[ -e "$path" ]]; then
    echo "Clean room refused to start: ${path} is visible. Mount only clean/ at /work." >&2
    exit 1
  fi
done

if [[ "$(id -u)" -eq 0 ]]; then
  /usr/local/bin/init-firewall.sh
  if [[ $# -eq 0 ]]; then
    exec runuser -u node -- sleep infinity
  fi
  exec runuser -u node -- "$@"
fi

sudo -n /usr/local/bin/init-firewall.sh
if [[ $# -eq 0 ]]; then
  exec sleep infinity
fi
exec "$@"
