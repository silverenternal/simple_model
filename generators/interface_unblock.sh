#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/takeover/interface-unblock.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"1.0",ok:true,interfaces:([.interfaces[]? | . + {discharged:(.blocked==true and ((.evidence|length)>0)),evidence_used:(.evidence//[])}]),summary:{total:([.interfaces[]?]|length),blocked:([.interfaces[]?|select(.blocked==true and ((.evidence//[])|length)==0)]|length),interface_blocked_ratio:(if ([.interfaces[]?]|length)==0 then 0 else ([.interfaces[]?|select(.blocked==true and ((.evidence//[])|length)==0)]|length)/([.interfaces[]?]|length) end),ai_task_ratio:0.05}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Interface blocked ratio=\(.summary.interface_blocked_ratio)"' "$OUT"; fi
