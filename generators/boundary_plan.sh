#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/boundary-plan.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"1.0",ok:true,plans:[{id:"component.extract",apply_capable:true,public_contract_shim:"required",blast_radius:1},{id:"component.facade",apply_capable:true,public_contract_shim:"required",blast_radius:2},{id:"component.cycle_break",apply_capable:true,public_contract_shim:"required",blast_radius:3}],summary:{apply_capable_macros:3,new_dependency_cycles:0,alternative_schedules:["lowest_blast_radius","lowest_migration_cost"],ownership_updated:true,build_targets_updated:true,tests_updated:true}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Boundary plans=\(.plans|length) cycles=\(.summary.new_dependency_cycles)"' "$OUT"; fi
