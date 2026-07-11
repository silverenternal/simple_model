#!/usr/bin/env bash
set -euo pipefail
INPUT=""
TITLE="simple_model report"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input) INPUT="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -n "$INPUT" && -f "$INPUT" ]] || { echo "[FAIL] --input file required" >&2; exit 2; }
data=$(jq . "$INPUT")
if [[ "$JSON_OUT" == "1" ]]; then
  jq -n --arg title "$TITLE" --argjson data "$data" '{schema_version:"1.0", ok:true, title:$title, data:$data}'
else
  echo "$TITLE"
  echo
  jq -r 'if has("summary") then (.summary|to_entries[]|"- " + .key + ": " + (.value|tostring)) else "- ok: " + (.ok|tostring) end' <<<"$data"
  jq -r 'if has("score") then "- score delta: " + (.score.delta|tostring) else empty end' <<<"$data"
fi
