#!/usr/bin/env bash
set -euo pipefail

SURFACES="generated/intelligence/dynamic-surfaces.json"
OUT="generated/intelligence/runtime-contracts.json"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --surfaces) SURFACES="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -f "$SURFACES" ]] || { echo "[FAIL] surfaces not found" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"
report=$(jq '{
  schema_version:"1.0", ok:true,
  contracts:((.nodes // []) | map({
    id:("runtime-contract:" + .id),
    surface_id:.id,
    allowed_commands:(.probe_commands // []),
    expected_observations:[.kind],
    secrets_policy:"deny",
    network_policy:"deny",
    replay_assertions:["surface id remains stable","risk level does not increase without review"],
    verification_status:(.verification_status // "unknown")
  })),
  summary:{contracts:((.nodes // [])|length), unobserved:((.nodes // [])|map(select((.verification_status // "") != "observed"))|length)}
}' "$SURFACES")
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Runtime contracts=" + (.summary.contracts|tostring)' <<<"$report"; fi
