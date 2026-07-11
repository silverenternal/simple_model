#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/control-flow-graph.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"1.0",ok:true,nodes:([.nodes[] | . + {flow_state:(.flow_state//"unknown"),language:(.language//"neutral")}]),edges:([.edges[] | . + {evidence:(.evidence//{source:"control_flow_graph",freshness:"current"}),flow_state:(.flow_state//"propagated")}]),summaries:([.summaries[]?]),diagnostics:([.nodes[]|select(.unknown_call==true)|{node_id:.id,kind:"unknown_call",explanation:"external summary unavailable"}]),summary:{nodes:(.nodes|length),edges:(.edges|length),unknown_calls:([.nodes[]|select(.unknown_call==true)]|length)}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Flow graph nodes=\(.summary.nodes) edges=\(.summary.edges)"' "$OUT"; fi
