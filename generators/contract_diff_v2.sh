#!/usr/bin/env bash
set -euo pipefail
BEFORE=""; AFTER=""; OUT="generated/intelligence/contract-diff.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --before) BEFORE="$2"; shift 2 ;; --after) AFTER="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$BEFORE" && -f "$AFTER" ]] || { echo "--before and --after required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq --slurpfile before "$BEFORE" --slurpfile after "$AFTER" -n '
  ($before[0] // {}) as $b | ($after[0] // {}) as $a
  | ((($b|keys)+($a|keys))|unique) as $keys
  | [ $keys[] as $k | if (($b|has($k))|not) then {path:$k,kind:"compatible_addition",before:null,after:$a[$k]} elif (($a|has($k))|not) then {path:$k,kind:"breaking_removal",before:$b[$k],after:null} elif ($b[$k] != $a[$k]) then {path:$k,kind:(if ($k|test("data|schema|migration")) then "data_migration" else "breaking_change" end),before:$b[$k],after:$a[$k]} else empty end ]
  | {schema_version:"1.0",ok:true,changes:.,summary:{changes:length,compatible_additions:([.[]|select(.kind=="compatible_addition")]|length),breaking:([.[]|select(.kind|startswith("breaking"))]|length),data_migrations:([.[]|select(.kind=="data_migration")]|length)}}
' > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Contract diff changes=\(.summary.changes) breaking=\(.summary.breaking)"' "$OUT"; fi
