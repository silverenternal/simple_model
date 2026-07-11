#!/usr/bin/env bash
set -euo pipefail
OUT="generated/intelligence/evidence-ledger.json"
JSON_OUT=0
INPUTS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input|-i) INPUTS+=("$2"); shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) INPUTS+=("$1"); shift ;;
  esac
done
[[ "${#INPUTS[@]}" -gt 0 ]] || { echo "at least one evidence input is required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
jq -s '
  def facts: [ .[] | if type=="array" then .[] elif .facts? then .facts[] else . end ];
  def state($fs):
    ([$fs[]|select(.freshness=="current")]) as $current
    | ([$current[].verdict]|unique) as $v
    | if ($current|length)==0 then (if ($fs|length)>0 then "stale" else "unknown" end)
      elif (($v|index("safe"))!=null and ($v|index("unsafe"))!=null) then "conflict"
      elif ([$current[].class]|unique|length)>1 then "corroborated"
      else "supported" end;
  facts | unique_by(.id) | sort_by(.subject,.id) | group_by(.subject)
  | map(. as $fs | {subject:.[0].subject,state:state($fs),verdict:(if state($fs)=="conflict" then "unknown" else ([$fs[]|select(.freshness=="current")|.verdict]|map(select(.!="unknown"))|first // "unknown") end),facts:$fs,
      provenance:([$fs[].provenance[]?]|unique|sort),invalidation_keys:([$fs[].invalidation_keys[]?]|unique|sort)})
  | {schema_version:"1.0",ok:true,summary:{subjects:length,conflicts:(map(select(.state=="conflict"))|length),stale:(map(select(.state=="stale"))|length)},subjects:.,join:{associative:true,commutative:true,idempotent:true}}
' "${INPUTS[@]}" > "$tmp"
hash="$(jq -S -c '.subjects' "$tmp" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
jq --arg hash "$hash" '.ledger_hash=$hash' "$tmp" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Evidence ledger subjects=\(.summary.subjects) conflicts=\(.summary.conflicts)"' "$OUT"; fi
