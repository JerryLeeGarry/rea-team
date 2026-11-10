#!/bin/bash
# Outbound allowlist for the rea-clean room.
# Adapted from the Claude Code reference devcontainer:
# https://github.com/anthropics/claude-code/blob/main/.devcontainer/init-firewall.sh
# Approach documented at https://code.claude.com/docs/en/devcontainer
#
# Remove the npm registry after dependency install
# ------------------------------------------------
# registry.npmjs.org is included only when /etc/rea-clean/allow-npm contains 1.
# The image bakes that flag from the ALLOW_NPM build arg (default 1) so the
# first boot can install packages. Leaving the registry on the allowlist lets
# the Rebuilder run `npx rea-agents` and pull analysis tools back across the wall.
#
# After dependencies are installed, rebuild with the registry removed:
#
#   ALLOW_NPM=0 docker compose up -d --build --force-recreate
#
# Confirm with scripts/check-wall.sh, and with a registry probe that must fail:
#
#   docker exec rea-clean curl -I --connect-timeout 5 https://registry.npmjs.org
#
# Editing this file inside the container does nothing: the running copy is
# /usr/local/bin/init-firewall.sh, and it reads only the root-owned flag file.
set -euo pipefail
IFS=$'\n\t'

ALLOW_NPM_FLAG=1
if [[ -f /etc/rea-clean/allow-npm ]]; then
  ALLOW_NPM_FLAG="$(tr -d '[:space:]' < /etc/rea-clean/allow-npm)"
fi
if [[ "$ALLOW_NPM_FLAG" != "0" && "$ALLOW_NPM_FLAG" != "1" ]]; then
  echo "ERROR: /etc/rea-clean/allow-npm must be 0 or 1, got: ${ALLOW_NPM_FLAG}" >&2
  exit 1
fi
echo "ALLOW_NPM=${ALLOW_NPM_FLAG} (0 means registry.npmjs.org stays off the allowlist)"

# 1. Extract Docker DNS info BEFORE any flushing
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

# Flush existing rules and delete existing ipsets
iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X
ipset destroy allowed-domains 2>/dev/null || true

# 2. Selectively restore ONLY internal Docker DNS resolution
if [[ -n "$DOCKER_DNS_RULES" ]]; then
  echo "Restoring Docker DNS rules..."
  iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
  iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
  # shellcheck disable=SC2086
  echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
  echo "No Docker DNS rules to restore"
fi

# First allow DNS and localhost before any restrictions
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT -p udp --sport 53 -j ACCEPT
iptables -A OUTPUT -p tcp --dport 22 -j ACCEPT
iptables -A INPUT -p tcp --sport 22 -m state --state ESTABLISHED -j ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

ipset create allowed-domains hash:net

echo "Fetching GitHub IP ranges..."
gh_ranges=$(curl -fsS --connect-timeout 10 https://api.github.com/meta || true)
if [[ -z "$gh_ranges" ]]; then
  echo "ERROR: Failed to fetch GitHub IP ranges" >&2
  exit 1
fi

if ! echo "$gh_ranges" | jq -e '.web and .api and .git' >/dev/null; then
  echo "ERROR: GitHub API response missing required fields" >&2
  exit 1
fi

echo "Processing GitHub IPs..."
added=0
# GitHub meta mixes IPv4 and IPv6. Keep IPv4 CIDRs (what this ipset stores)
# and skip everything else instead of aborting the allowlist.
while read -r cidr; do
  [[ -z "$cidr" ]] && continue
  if [[ ! "$cidr" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}/[0-9]{1,2}$ ]]; then
    echo "Skipping non-IPv4 GitHub range: $cidr"
    continue
  fi
  echo "Adding GitHub range $cidr"
  ipset add allowed-domains "$cidr"
  added=$((added + 1))
done < <(echo "$gh_ranges" | jq -r '(.web + .api + .git)[]' | grep -E '^[0-9.]+/[0-9]+$' | aggregate -q)

if [[ "$added" -eq 0 ]]; then
  echo "ERROR: No IPv4 GitHub ranges added" >&2
  exit 1
fi

domains=(
  "api.anthropic.com"
  "sentry.io"
  "statsig.com"
  "marketplace.visualstudio.com"
  "vscode.blob.core.windows.net"
  "update.code.visualstudio.com"
)
# Dependency install needs the registry. Drop this entry (ALLOW_NPM=0) before
# the Rebuilder runs so `npx rea-agents` cannot reach npm.
if [[ "$ALLOW_NPM_FLAG" != "0" ]]; then
  domains=("registry.npmjs.org" "${domains[@]}")
fi

for domain in "${domains[@]}"; do
  echo "Resolving $domain..."
  ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
  if [[ -z "$ips" ]]; then
    echo "ERROR: Failed to resolve $domain" >&2
    exit 1
  fi

  while read -r ip; do
    [[ -z "$ip" ]] && continue
    if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
      echo "ERROR: Invalid IP from DNS for $domain: $ip" >&2
      exit 1
    fi
    echo "Adding $ip for $domain"
    ipset add allowed-domains "$ip"
  done < <(printf '%s\n' "$ips")
done

HOST_IP=$(ip route | awk '/default/ {print $3; exit}')
if [[ -z "$HOST_IP" ]]; then
  echo "ERROR: Failed to detect host IP" >&2
  exit 1
fi

HOST_NETWORK=$(echo "$HOST_IP" | sed 's/\.[0-9]*$/.0\/24/')
echo "Host network detected as: $HOST_NETWORK"

iptables -A INPUT -s "$HOST_NETWORK" -j ACCEPT
iptables -A OUTPUT -d "$HOST_NETWORK" -j ACCEPT

iptables -P INPUT DROP
iptables -P FORWARD DROP
iptables -P OUTPUT DROP

iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m set --match-set allowed-domains dst -j ACCEPT
iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

# The reference script is IPv4-only. Drop IPv6 egress so it cannot bypass the allowlist.
if command -v ip6tables >/dev/null 2>&1 && ip6tables -L >/dev/null 2>&1; then
  ip6tables -F || true
  ip6tables -X || true
  ip6tables -A INPUT -i lo -j ACCEPT || true
  ip6tables -A OUTPUT -o lo -j ACCEPT || true
  ip6tables -P INPUT DROP || true
  ip6tables -P FORWARD DROP || true
  ip6tables -P OUTPUT DROP || true
  ip6tables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT || true
  ip6tables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT || true
  ip6tables -A OUTPUT -j REJECT --reject-with icmp6-adm-prohibited || true
fi

echo "Firewall configuration complete"
echo "Verifying firewall rules..."
if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
  echo "ERROR: Firewall verification failed - was able to reach https://example.com" >&2
  exit 1
else
  echo "Firewall verification passed - unable to reach https://example.com as expected"
fi

if ! curl --connect-timeout 5 https://api.github.com/zen >/dev/null 2>&1; then
  echo "ERROR: Firewall verification failed - unable to reach https://api.github.com" >&2
  exit 1
else
  echo "Firewall verification passed - able to reach https://api.github.com as expected"
fi

if [[ "$ALLOW_NPM_FLAG" == "0" ]]; then
  if curl --connect-timeout 5 https://registry.npmjs.org >/dev/null 2>&1; then
    echo "ERROR: npm registry is still reachable after ALLOW_NPM=0" >&2
    exit 1
  fi
  echo "Firewall verification passed - npm registry is not reachable"
fi
