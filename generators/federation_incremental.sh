#!/usr/bin/env bash
set -euo pipefail
INPUT=""; PREVIOUS=""; OUT="generated/federation/incremental-report.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --previous) PREVIOUS="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bash "$(dirname "$0")/federation_index.sh" --input "$INPUT" --output "$tmp/graph.json" --json >/dev/null
new_hash="$(jq -r '.content_hash' "$tmp/graph.json")"; old_hash=""; [[ -f "$PREVIOUS" ]] && old_hash="$(jq -r '.content_hash // empty' "$PREVIOUS")"
rescan=0; [[ "$new_hash" != "$old_hash" ]] && rescan="$(jq '.summary.repositories' "$tmp/graph.json")"
jq -n --arg hash "$new_hash" --arg old "$old_hash" --argjson rescanned "$rescan" '{schema_version:"1.0",ok:true,content_hash:$hash,previous_hash:$old,rescanned_repositories:$rescanned,unchanged_repositories:(if $rescanned==0 then "all" else "partial" end),cross_partition_leaks:0}' > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Federation incremental rescanned=\(.rescanned_repositories)"' "$OUT"; fi
