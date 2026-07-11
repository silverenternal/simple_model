#!/usr/bin/env bash
set -euo pipefail
BASELINE=""; CANDIDATE=""; OUT="generated/intelligence/capture-stability.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --baseline|-b) BASELINE="$2"; shift 2 ;;
    --candidate|-c) CANDIDATE="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -f "$BASELINE" && -f "$CANDIDATE" ]] || { echo "--baseline and --candidate required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq -n --slurpfile base "$BASELINE" --slurpfile cand "$CANDIDATE" '
  ($base[0].matches | map({capture,stable_id,symbol_identity})) as $b
  | ($cand[0].matches | map({capture,stable_id,symbol_identity})) as $c
  | ($b == $c) as $stable
  | {schema_version:"1.0",ok:true,stable:$stable,baseline_count:($b|length),candidate_count:($c|length),changed:(if $stable then [] else [{code:"capture_identity_changed",severity:"error",message:"typed or symbol identity changed across harmless syntax/style variation"}] end),apply_allowed:($stable and ($cand[0].summary.ambiguous|not))}
' > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Capture stability stable=\(.stable) apply=\(.apply_allowed)"' "$OUT"; fi
jq -e '.ok==true' "$OUT" >/dev/null
