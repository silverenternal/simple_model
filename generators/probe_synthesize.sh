#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/probe-plan.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"2.0",ok:true,probes:([.obligations[]? | {id:("probe:"+.id),obligation:.id,argv:["git","status","--short"],read_only:true,network:false,network_allowlist:[],timeout_ms:(.timeout_ms//1000),resource_limits:{memory_mb:(.memory_mb//128)},updates:[.evidence_node]}]),budget:{max_probes:(.budget.max_probes//10),timeout_ms:(.budget.timeout_ms//1000)},policy:{read_only:true,network_allowlist:(.budget.network_allowlist//[]),untrusted_content_as_argv:true},summary:{obligations:([.obligations[]?]|length),probes:([.obligations[]?]|length),unsafe_probe_executions:0,blocker_discharge_rate:(if ([.obligations[]?|select(.discharged==true)]|length)==0 then 0 else (([.obligations[]?|select(.discharged==true)]|length)/([.obligations[]?]|length)) end)}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Probe plan probes=\(.summary.probes) discharge=\(.summary.blocker_discharge_rate)"' "$OUT"; fi
