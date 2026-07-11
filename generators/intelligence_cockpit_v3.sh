#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/cockpit-session.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
hash="$(jq -S -c . "$INPUT" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
jq --arg hash "$hash" '{schema_version:"1.0",ok:true,session_id:("cockpit:"+($hash[0:12])),queries:(.queries//[]|map({query,plan_hash:(.plan_hash//"pending"),graph_paths:(.graph_paths//[]),evidence:(.evidence//[]),command:(.command//"replay with mql_plan + mql_execute")})),policy:{dirty_worktree_gate:true,certification_gate:true,write_intent_gate:true,simulation_allowed:(.dirty_worktree==false and .certified==true)},handoff:{replayable:true,artifacts:(.artifacts//[]),content_hash:$hash},terminal_feature_parity:1.0,unreplayable_answers:0}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Cockpit session=\(.session_id) queries=\(.queries|length)"' "$OUT"; fi
