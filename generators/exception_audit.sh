#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/policy/exception-audit.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"2.0",ok:true,exceptions:([.exceptions[]? | {id,identity:(.identity//"unknown"),plan_hash,scope,environment,expires_at,reason,waiver_allowed:false,required_proofs:(.required_proofs//["false_safe_apply","rollback","provenance","audit_log"])}]),summary:{unattributed_exceptions:([.exceptions[]?|select((.identity//"unknown")=="unknown")]|length),waivers_cannot_suppress:["false_safe_apply","rollback","provenance","audit_log"]}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Exceptions=\(.exceptions|length) unattributed=\(.summary.unattributed_exceptions)"' "$OUT"; fi
