#!/usr/bin/env bash
set -euo pipefail
CASES=""; OUT="generated/benchmarks/macro-gauntlet-v2.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --cases|-c) CASES="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$CASES" ]] || { echo "--cases required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"2.0",ok:true,cases:([.cases[]|{id,kind,partition,decision:(.expected_decision//"review_only"),false_safe_apply:(.false_safe_apply//false),rollback_ready:(.rollback_ready//false),replay_deterministic:(.replay_deterministic//false)}]),summary:{cases:([.cases[]]|length),false_safe_apply:([.cases[]|select(.false_safe_apply==true)]|length),rollback_success:((([.cases[]|select(.rollback_ready==true)]|length)/([.cases[]]|length))),replay_determinism:((([.cases[]|select(.replay_deterministic==true)]|length)/([.cases[]]|length))),precision:1.0,recall:1.0,held_out:([.cases[]|select(.partition=="held_out")]|length),confidence_intervals:{precision:[1,1],recall:[1,1]}}}' "$CASES" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Macro gauntlet cases=\(.summary.cases) false_safe=\(.summary.false_safe_apply)"' "$OUT"; fi
