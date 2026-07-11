#!/usr/bin/env bash
set -euo pipefail
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --root) ROOT="$2"; shift 2 ;; --struct|-s) STRUCT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
ROOT="$(cd "$ROOT" && pwd)"
tests=$(find "$ROOT" -type f \( -name '*test*.*' -o -name '*spec*.*' \) ! -path '*/node_modules/*' ! -path '*/target/*' | sort | sed "s#^$ROOT/##" | jq -R -s 'split("\n")[:-1]')
components="[]"; [[ -f "$STRUCT" ]] && components=$(jq '[.modules[]? as $m | $m.components[]? | {module:$m.name, component:.name, path:(.path//""), tests:[]}]' "$STRUCT")
report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --argjson tests "$tests" --argjson components "$components" '{schema_version:"1.0", ok:true, root:$root, struct:$struct, summary:{tests:($tests|length), components:($components|length), untested_components:($components|length)}, tests:($tests|map({path:., kind:(if test("contract") then "contract" elif test("integration") then "integration" else "unit" end), linked_symbols:[], linked_contracts:[]})), components:$components, gaps:($components|map({component:.component, type:"missing_test_mapping", remediation:"add or map tests for public interfaces"}))}')
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Test Graph tests=" + (.summary.tests|tostring)' <<<"$report"; fi
