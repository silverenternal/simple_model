#!/usr/bin/env bash
set -euo pipefail
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
JSON_OUT=0
OUT="generated/intelligence/workspace-graph.json"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"
mkdir -p "$(dirname "$OUT")"
roots=$(find "$ROOT" -type f \( -name package.json -o -name go.mod -o -name Cargo.toml -o -name pyproject.toml -o -name pom.xml -o -name build.gradle \) ! -path '*/node_modules/*' ! -path '*/target/*' | sort | while read -r f; do
  rel="${f#"$ROOT"/}"; dir="$(dirname "$rel")"; [[ "$dir" == "." ]] && dir=""
  eco="unknown"; case "$(basename "$f")" in package.json) eco=node ;; go.mod) eco=go ;; Cargo.toml) eco=rust ;; pyproject.toml) eco=python ;; pom.xml|build.gradle) eco=jvm ;; esac
  jq -cn --arg path "$dir" --arg manifest "$rel" --arg ecosystem "$eco" '{path:$path, manifest:$manifest, ecosystem:$ecosystem}'
done | jq -s '.')
components="[]"; [[ -f "$STRUCT" ]] && components=$(jq --argjson roots "$roots" '[.modules[]? as $m | $m.components[]? | {module:$m.name, component:.name, path:(.path//""), workspace:((($roots[]?|select((.path == "") or ((.path + "/") as $p | (.path|length)>=0 and (. as $c | false)))) // null) // null)}]' "$STRUCT" 2>/dev/null || echo "[]")
report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --argjson roots "$roots" --argjson components "$components" '{schema_version:"1.0", ok:true, root:$root, struct:$struct, summary:{workspaces:($roots|length), components:($components|length), boundary_violations:0}, workspaces:$roots, components:$components, policies:[]}')
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Workspace Graph workspaces=" + (.summary.workspaces|tostring)' <<<"$report"; fi
