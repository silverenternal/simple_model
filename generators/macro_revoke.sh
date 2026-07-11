#!/usr/bin/env bash
set -euo pipefail
REGISTRY=""; MACRO_ID=""; REASON=""; OUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in --registry|-r) REGISTRY="$2"; shift 2 ;; --macro-id|-m) MACRO_ID="$2"; shift 2 ;; --reason) REASON="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$REGISTRY" && -n "$MACRO_ID" && -n "$REASON" ]] || { echo "--registry --macro-id --reason required" >&2; exit 64; }
[[ -n "$OUT" ]] || OUT="$REGISTRY"
jq --arg id "$MACRO_ID" --arg reason "$REASON" '(.macros[]|select(.id==$id)) as $target | if $target==null then {schema_version:"2.0",ok:false,error:{code:"macro_not_found"}} else .macros |= map(if .id==$id then .status="revoked" | .apply_eligible=false else . end) | .revocations=((.revocations//[])+[{macro_id:$id,reason:$reason,audit_preserved:true}]) | . end' "$REGISTRY" > "$OUT.tmp"
mv "$OUT.tmp" "$OUT"
cat "$OUT"
jq -e '.ok!=false' "$OUT" >/dev/null
