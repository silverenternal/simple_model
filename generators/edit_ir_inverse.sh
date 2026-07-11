#!/usr/bin/env bash
set -euo pipefail
IR=""; APPLIED=""; OUT=""
while [[ $# -gt 0 ]]; do case "$1" in --ir) IR="$2"; shift 2;; --applied) APPLIED="$2"; shift 2;; --output|-o) OUT="$2"; shift 2;; --json) shift;; *) echo "unknown arg: $1" >&2; exit 64;; esac; done
[[ -f "$IR" && -f "$APPLIED" && -n "$OUT" ]] || { echo "--ir --applied --output required" >&2; exit 64; }
applied_hash="$( (sha256sum "$APPLIED" 2>/dev/null || shasum -a 256 "$APPLIED")|awk '{print $1}')"
jq --arg hash "$applied_hash" '
  .source_hash as $original_hash
  | .edits |= (sort_by(.capture.start) | reduce .[] as $e ({delta:0,out:[]};
    ($e.capture.start + .delta) as $start | ($e.replacement|length) as $len
    | .out += [$e | .capture.start=$start | .capture.end=($start+$len) | .capture.expected_hash=$hash | .original=$e.replacement | .replacement=$e.original]
    | .delta += (($e.replacement|length)-($e.original|length))) | .out)
  | .source_hash=$hash | .inverse_of=$original_hash
' "$IR" > "$OUT"
cat "$OUT"
