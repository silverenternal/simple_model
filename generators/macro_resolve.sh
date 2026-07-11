#!/usr/bin/env bash
set -euo pipefail
REGISTRY=""; MACRO_ID=""; OUT="generated/macros/macro-resolution.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --registry|-r) REGISTRY="$2"; shift 2 ;; --macro-id|-m) MACRO_ID="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$REGISTRY" && -n "$MACRO_ID" ]] || { echo "--registry and --macro-id required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq --arg id "$MACRO_ID" '(.macros[]|select(.id==$id)) as $m | {schema_version:"1.0",ok:($m!=null),macro:$m,resolution_order:(.resolution_order),apply_allowed:($m.apply_eligible//false),reason:(if $m==null then "macro_not_found" elif ($m.apply_eligible//false) then "certificate_and_diversity_verified" else "not_eligible" end)}' "$REGISTRY" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Resolve \(.macro.id // \"unknown\") apply=\(.apply_allowed)"' "$OUT"; fi
jq -e '.ok==true' "$OUT" >/dev/null
