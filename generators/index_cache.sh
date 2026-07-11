#!/usr/bin/env bash
set -euo pipefail
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
CACHE="generated/.cache/simple_model/index-cache.json"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --cache) CACHE="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"
mkdir -p "$(dirname "$CACHE")"
old="[]"; [[ -f "$CACHE" ]] && old=$(jq -c '.files // []' "$CACHE" 2>/dev/null || echo "[]")
struct_hash=""; [[ -f "$STRUCT" ]] && struct_hash=$( (sha256sum "$STRUCT" 2>/dev/null || shasum -a 256 "$STRUCT") | awk '{print $1}' )
files=$(find "$ROOT" -type f \( -name '*.py' -o -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.go' -o -name '*.rs' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' \) ! -path '*/.git/*' ! -path '*/node_modules/*' ! -path '*/target/*' | sort | while read -r f; do
  rel="${f#"$ROOT"/}"
  h=$( (sha256sum "$f" 2>/dev/null || shasum -a 256 "$f") | awk '{print $1}' )
  status=$(jq -r --arg p "$rel" --arg h "$h" --arg s "$struct_hash" '[.[]|select(.path==$p and .hash==$h and .struct_hash==$s)]|length' <<<"$old")
  [[ "$status" == "0" ]] && st="miss" || st="hit"
  jq -cn --arg path "$rel" --arg hash "$h" --arg struct_hash "$struct_hash" --arg status "$st" '{path:$path, hash:$hash, struct_hash:$struct_hash, parser_version:"semantic-ir-v2", status:$status}'
done | jq -s '.')
report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --arg cache "$CACHE" --argjson files "$files" '{schema_version:"1.0", ok:true, root:$root, struct:$struct, cache:$cache, summary:{files:($files|length), hits:($files|map(select(.status=="hit"))|length), misses:($files|map(select(.status=="miss"))|length), invalidations:($files|map(select(.status=="miss"))|length)}, files:$files}')
printf '%s\n' "$report" > "$CACHE"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Index Cache files=" + (.summary.files|tostring) + " hits=" + (.summary.hits|tostring) + " misses=" + (.summary.misses|tostring)' <<<"$report"; fi
