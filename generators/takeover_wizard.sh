#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT_DIR="generated/takeover"; RESUME=0; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output-dir) OUT_DIR="$2"; shift 2 ;; --resume) RESUME=1; shift ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$OUT_DIR"
hash="$(jq -S -c . "$INPUT" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
if [[ "$RESUME" == 1 && -f "$OUT_DIR/session.json" ]] && jq -e --arg hash "$hash" '.input_hash==$hash' "$OUT_DIR/session.json" >/dev/null; then
  jq --arg hash "$hash" '.status="resumed" | .input_hash=$hash' "$OUT_DIR/session.json" > "$OUT_DIR/session.json.tmp"; mv "$OUT_DIR/session.json.tmp" "$OUT_DIR/session.json"
  [[ "$JSON_OUT" == 1 ]] && cat "$OUT_DIR/session.json" || jq -r '"Takeover resumed \(.session_id)"' "$OUT_DIR/session.json"; exit 0
fi
jq --arg hash "$hash" --arg id "$(jq -r '.project_id//"project"' "$INPUT")" '{schema_version:"1.0",session_id:($id+":"+($hash[0:12])),status:"planned",input_hash:$hash,non_destructive:true,writes:["struct.proposed.json","parser-config.json","interface-commitments.json","optimization-queue.json"],macro_plan:{mode:"review_only",writes:[]},interfaces:{total:([.interfaces[]?]|length),blocked:([.interfaces[]?|select(.blocked==true)]|length)},ai_tasks:[{kind:"owner",bounded:true},{kind:"compatibility_choice",bounded:true}],ai_task_ratio:0.05}' "$INPUT" > "$OUT_DIR/session.json"
jq -n '{schema_version:"1.0",writes:[],mode:"review_only"}' > "$OUT_DIR/macro-plan.json"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT_DIR/session.json"; else jq -r '"Takeover planned \(.session_id)"' "$OUT_DIR/session.json"; fi
