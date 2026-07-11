#!/usr/bin/env bash
set -euo pipefail

MODE="merge"
DIR="generated/intelligence/program-graph-v3.partitions"
OUT="generated/intelligence/program-graph-v3.merged.json"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --merge) MODE="merge"; shift ;;
    --dir) DIR="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ "$MODE" == "merge" ]] || exit 64
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp)"; trap 'rm -f "$tmp"' EXIT
jq -s '{schema_version:"3.0",ok:true,nodes:([.[].nodes[]?]|unique_by(.id)|sort_by(.id)),edges:([.[].edges[]?]|unique_by(.id)|sort_by(.id)),partitions:[.[]|{kind,hash}]|sort_by(.kind),graph_hash:"pending"}' "$DIR"/*.json > "$tmp"
hash="$(jq -S -c '{nodes,edges,partitions}' "$tmp" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
jq --arg hash "$hash" '.graph_hash=$hash | .summary={nodes:(.nodes|length),edges:(.edges|length),partitions:(.partitions|length)}' "$tmp" > "$OUT"
cat "$OUT"
