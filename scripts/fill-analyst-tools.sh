#!/usr/bin/env bash
# Fill the analyst tools line from `rea doctor --json` (lab/analysis/doctor.json).
#
# Accepts several shapes, because the doctor schema is not one stable list:
#   - objects with a name plus surface or an input/output schema
#   - arrays named tools, mcp_tools, mcpTools, tool_names, or toolNames
#   - tool_availability-style groups: { names: [...], availability|available|reason }
# Names are written as mcp__rea__<name>. Read, Grep, Glob, and Write stay.
#
# Needs Node.js, or jq when node is not on PATH. Both paths are checked by
# --self-test. When the file parses but no tool-shaped names are present
# (counts only, for example identity.catalog.counts.mcp_tools), the script
# exits 2 and prints a manual fallback. It does not invent tool names.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
  cat <<'EOF'
Usage: scripts/fill-analyst-tools.sh [--dry-run] [doctor.json] [analyst.md]
       scripts/fill-analyst-tools.sh --self-test

Default doctor.json: lab/analysis/doctor.json
Default analyst.md:  lab/.claude/agents/analyst.md

Write doctor.json from the lab side (not inside rea-clean):

  cd lab && rea doctor --json > analysis/doctor.json
EOF
}

# jq fallback. Keep the name rules aligned with the node extractor below.
# shellcheck disable=SC2016 # jq uses $n / $o; this string must not expand.
JQ_FILTER='
def bare:
  if type != "string" then empty
  elif startswith("mcp__rea__") then .[10:]
  else . end;
def denied: ["ok","true","false","name","id","configuration","registration","identity","healthy","skill","client","version","node","npm","doctor","checks","detail","remediation","error","status","path","type","mode"];
def allowed:
  bare as $n
  | select($n | test("^[A-Za-z][A-Za-z0-9_]{1,127}$"))
  | select(($n | contains("_")) or ((denied | index($n | ascii_downcase)) == null))
  | $n;
def from_tool_object:
  if type == "object"
     and (.name | type == "string")
     and (.surface != null or .input_schema != null or .inputSchema != null or .output_schema != null or .outputSchema != null)
  then .name | allowed
  else empty end;
[
  (if type == "array" then .[] | select(type == "string") | allowed else empty end),
  ( .. | objects | . as $o
    | (
        (if ($o.surface != null or $o.input_schema != null or $o.inputSchema != null or $o.output_schema != null or $o.outputSchema != null)
            and ($o.name | type == "string")
         then $o.name | allowed else empty end),
        (if (($o | has("availability")) or ($o | has("available")) or ($o | has("reason")))
            and ($o.names | type == "array")
         then $o.names[] | allowed else empty end),
        ($o | to_entries[]
          | select(.key | test("^(tools|mcp_tools|mcpTools|tool_names|toolNames)$"))
          | .value
          | if type == "array"
            then .[]
              | if type == "string" then allowed
                elif type == "object" then from_tool_object
                else empty end
            else empty end)
      )
  )
] | unique | .[]
'

manual_fallback() {
  local doctor="$1"
  cat >&2 <<EOF
Could not find REA tool names in ${doctor}.
This script does not guess. doctor.json often carries counts only
(identity.catalog.counts.mcp_tools) or check names that are not MCP tools.

Shapes it does read:
  - objects with "name" plus "surface" or an input/output schema
  - arrays named tools, mcp_tools, mcpTools, tool_names, or toolNames
  - objects with "names" plus availability, available, or reason

Manual fallback:
  1. Inspect whatever name fields the file actually has:
       jq -r '.. | objects | .name? // empty' ${doctor}
  2. On the lab side, open Claude Code and read the live rea tool list.
     Usable names look like mcp__rea__binary_session. Copy those, do not invent them.
  3. Edit the tools line in lab/.claude/agents/analyst.md so it stays inside the frontmatter:
       tools: Read, Grep, Glob, Write, mcp__rea__<name>, mcp__rea__<name>
     Keep Read, Grep, Glob, and Write. Do not add Bash.
EOF
}

extract_with_node() {
  local file="$1"
  node - "$file" <<'JS'
const fs = require('fs');
const file = process.argv[2];
const DENY = new Set([
  'ok', 'true', 'false', 'name', 'id', 'configuration', 'registration',
  'identity', 'healthy', 'skill', 'client', 'version', 'node', 'npm',
  'doctor', 'checks', 'detail', 'remediation', 'error', 'status', 'path',
  'type', 'mode',
]);

function allowed(name) {
  if (!/^[A-Za-z][A-Za-z0-9_]{1,127}$/.test(name)) return false;
  if (!name.includes('_') && DENY.has(name.toLowerCase())) return false;
  return true;
}

function add(raw, acc) {
  if (typeof raw !== 'string') return;
  let name = raw.trim();
  const prefix = 'mcp__rea__';
  if (name.startsWith(prefix)) name = name.slice(prefix.length);
  if (!allowed(name)) return;
  acc.add(name);
}

function isToolObject(value) {
  return Boolean(value)
    && typeof value === 'object'
    && !Array.isArray(value)
    && typeof value.name === 'string'
    && (value.surface != null
      || value.input_schema != null
      || value.inputSchema != null
      || value.output_schema != null
      || value.outputSchema != null);
}

function visit(node, acc) {
  if (Array.isArray(node)) {
    node.forEach((item) => visit(item, acc));
    return;
  }
  if (!node || typeof node !== 'object') return;
  if (isToolObject(node)) add(node.name, acc);
  if (Array.isArray(node.names)
    && (Object.prototype.hasOwnProperty.call(node, 'availability')
      || Object.prototype.hasOwnProperty.call(node, 'available')
      || Object.prototype.hasOwnProperty.call(node, 'reason'))) {
    node.names.forEach((name) => add(name, acc));
  }
  for (const [key, value] of Object.entries(node)) {
    if (/^(tools|mcp_tools|mcpTools|tool_names|toolNames)$/.test(key) && Array.isArray(value)) {
      for (const item of value) {
        if (typeof item === 'string') add(item, acc);
        else if (isToolObject(item)) add(item.name, acc);
      }
    }
    visit(value, acc);
  }
}

let text;
try {
  text = fs.readFileSync(file, 'utf8');
} catch (err) {
  console.error(`cannot read ${file}: ${err.message}`);
  process.exit(1);
}
if (text.charCodeAt(0) === 0xfeff) text = text.slice(1);
let data;
try {
  data = JSON.parse(text);
} catch (err) {
  console.error(`cannot parse ${file}: ${err.message}`);
  process.exit(1);
}
const acc = new Set();
if (Array.isArray(data)) {
  for (const item of data) {
    if (typeof item === 'string') add(item, acc);
  }
}
visit(data, acc);
const names = [...acc].sort((a, b) => (a < b ? -1 : a > b ? 1 : 0));
if (names.length) process.stdout.write(`${names.join('\n')}\n`);
JS
}

extract_with_jq() {
  local file="$1"
  jq -r "$JQ_FILTER" "$file" | sort -u
}

extract_names() {
  local file="$1"
  if command -v node >/dev/null 2>&1; then
    extract_with_node "$file"
  elif command -v jq >/dev/null 2>&1; then
    extract_with_jq "$file"
  else
    echo "Need node or jq to read doctor.json." >&2
    return 1
  fi
}

build_tools_value() {
  local line="Read, Grep, Glob, Write"
  local name
  while IFS= read -r name; do
    [[ -z "$name" ]] && continue
    if [[ "$name" == mcp__* ]]; then
      line+=", ${name}"
    else
      line+=", mcp__rea__${name}"
    fi
  done
  printf '%s' "$line"
}

update_agent() {
  local agent="$1"
  local line="$2"
  local tmp
  tmp="$(mktemp)"
  if ! TOOLS_LINE="tools: \"${line}\"" awk '
    NR == 1 && $0 == "---" { in_fm = 1; print; next }
    in_fm && $0 == "---" { in_fm = 0; print; next }
    in_fm && $0 ~ /^tools:/ && !done { print ENVIRON["TOOLS_LINE"]; done = 1; next }
    { print }
    END { if (!done) exit 3 }
  ' "$agent" > "$tmp"; then
    rm -f "$tmp"
    echo "No tools: line in the frontmatter of ${agent}" >&2
    return 1
  fi
  mv "$tmp" "$agent"
}

assert_eq() {
  local label="$1"
  local got="$2"
  local want="$3"
  if [[ "$got" != "$want" ]]; then
    echo "self-test failed: ${label}" >&2
    echo "got:  [${got}]" >&2
    echo "want: [${want}]" >&2
    return 1
  fi
}

run_self_test() {
  local workdir file got
  workdir="$(mktemp -d)"
  # shellcheck disable=SC2064
  trap "rm -rf ${workdir}" RETURN

  cat > "${workdir}/catalog.json" <<'EOF'
{"identity":{"catalog":{"counts":{"mcp_tools":2},"tools":[{"name":"binary_session","surface":"session","input_schema":{}},{"name":"configuration","ok":false}]}}}
EOF
  cat > "${workdir}/groups.json" <<'EOF'
{"tool_availability":{"groups":[{"names":["inspect_strings","decompile_function"],"availability":"ready"}]}}
EOF
  cat > "${workdir}/checks.json" <<'EOF'
{"healthy":false,"checks":[{"name":"configuration","ok":false},{"name":"skill:identity","ok":false}]}
EOF
  cat > "${workdir}/strings.json" <<'EOF'
{"tools":["mcp__rea__search_strings","analyze_module","ok"]}
EOF
  cat > "${workdir}/counts.json" <<'EOF'
{"identity":{"catalog":{"counts":{"mcp_tools":207}}}}
EOF
  cat > "${workdir}/root.json" <<'EOF'
["mcp__rea__load_index","rank_results","ok"]
EOF

  got="$(extract_with_node "${workdir}/catalog.json")"
  assert_eq "node catalog" "$got" "binary_session"
  got="$(extract_with_node "${workdir}/groups.json")"
  assert_eq "node groups" "$got" $'decompile_function\ninspect_strings'
  got="$(extract_with_node "${workdir}/checks.json")"
  assert_eq "node checks" "$got" ""
  got="$(extract_with_node "${workdir}/strings.json")"
  assert_eq "node strings" "$got" $'analyze_module\nsearch_strings'
  got="$(extract_with_node "${workdir}/counts.json")"
  assert_eq "node counts" "$got" ""
  got="$(extract_with_node "${workdir}/root.json")"
  assert_eq "node root array" "$got" $'load_index\nrank_results'

  if command -v jq >/dev/null 2>&1; then
    for file in catalog.json groups.json checks.json strings.json counts.json root.json; do
      got="$(extract_with_jq "${workdir}/${file}" || true)"
      local node_got
      node_got="$(extract_with_node "${workdir}/${file}")"
      assert_eq "jq matches node on ${file}" "$got" "$node_got"
    done
    echo "self-test passed (node and jq)"
  else
    echo "self-test passed (node; jq not installed)"
  fi

  cat > "${workdir}/agent.md" <<'EOF'
---
name: analyst
description: test agent
tools: Read, Grep, Glob, Write, mcp__rea__<tool names from doctor.json>
model: opus
---

tools: leave this body line alone
EOF
  local value
  value="$(extract_with_node "${workdir}/strings.json" | build_tools_value)"
  update_agent "${workdir}/agent.md" "$value"
  grep -q '^tools: "Read, Grep, Glob, Write, mcp__rea__analyze_module, mcp__rea__search_strings"$' "${workdir}/agent.md"
  grep -q '^tools: leave this body line alone$' "${workdir}/agent.md"
  echo "self-test passed (frontmatter rewrite)"
}

dry=0
self=0
positionals=()
for arg in "$@"; do
  case "$arg" in
    --self-test) self=1 ;;
    --dry-run) dry=1 ;;
    -h|--help) usage; exit 0 ;;
    --) ;;
    -*)
      echo "unknown option: $arg" >&2
      usage >&2
      exit 1
      ;;
    *) positionals+=("$arg") ;;
  esac
done

if [[ "$self" -eq 1 ]]; then
  if ! command -v node >/dev/null 2>&1; then
    echo "self-test needs node" >&2
    exit 1
  fi
  run_self_test
  exit 0
fi

doctor="$ROOT/lab/analysis/doctor.json"
agent="$ROOT/lab/.claude/agents/analyst.md"
if [[ ${#positionals[@]} -ge 1 ]]; then
  doctor="${positionals[0]}"
fi
if [[ ${#positionals[@]} -ge 2 ]]; then
  agent="${positionals[1]}"
fi

if [[ ! -f "$doctor" ]]; then
  echo "missing ${doctor}" >&2
  echo "Create it from the lab side: cd lab && rea doctor --json > analysis/doctor.json" >&2
  exit 1
fi
if [[ ! -f "$agent" ]]; then
  echo "missing ${agent}" >&2
  exit 1
fi

names=""
if ! names="$(extract_names "$doctor")"; then
  exit 1
fi
if [[ -z "${names//[[:space:]]/}" ]]; then
  manual_fallback "$doctor"
  exit 2
fi

value="$(printf '%s\n' "$names" | build_tools_value)"
count="$(printf '%s\n' "$names" | sed '/^$/d' | wc -l | tr -d ' ')"

if [[ "$dry" -eq 1 ]]; then
  printf 'tools: "%s"\n' "$value"
  echo "dry-run: ${count} rea tools from ${doctor}" >&2
  exit 0
fi

update_agent "$agent" "$value"
echo "updated ${agent} (${count} rea tools from ${doctor})"
