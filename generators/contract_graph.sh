#!/usr/bin/env bash
set -euo pipefail

ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    -h|--help) echo "contract_graph.sh --root <repo> --struct <struct> [--json]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
find "$ROOT" -type f \( -iname '*openapi*.json' -o -iname '*openapi*.yaml' -o -iname '*.graphql' -o -iname '*.proto' -o -iname '*.sql' -o -iname '*asyncapi*.json' -o -iname '*asyncapi*.yaml' \) | sort | while read -r f; do
  rel="${f#"$ROOT"/}"
  case "$f" in
    *.graphql) kind="graphql"; name="$(basename "$f")" ;;
    *.proto) kind="grpc"; name="$(basename "$f")" ;;
    *.sql) kind="database"; name="$(basename "$f")" ;;
    *asyncapi*) kind="asyncapi"; name="$(basename "$f")" ;;
    *) kind="openapi"; name="$(basename "$f")" ;;
  esac
  hash=$( (sha256sum "$f" 2>/dev/null || shasum -a 256 "$f") | awk '{print $1}' )
  jq -cn --arg id "$kind:$rel" --arg kind "$kind" --arg name "$name" --arg path "$rel" --arg hash "$hash" '{id:$id, kind:$kind, name:$name, path:$path, hash:$hash, parser:"contract_file_parser", confidence:0.85, diff_class:"unknown", operations:[]}'
done > "$tmp"
contracts=$(jq -s '.' "$tmp")
report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --argjson contracts "$contracts" '{schema_version:"1.0", ok:true, root:$root, struct:$struct, summary:{contracts:($contracts|length), openapi:($contracts|map(select(.kind=="openapi"))|length), graphql:($contracts|map(select(.kind=="graphql"))|length), grpc:($contracts|map(select(.kind=="grpc"))|length), database:($contracts|map(select(.kind=="database"))|length)}, contracts:$contracts}')
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Contract Graph contracts=" + (.summary.contracts|tostring)' <<<"$report"; fi
