#!/usr/bin/env bash
set -euo pipefail
IR=""; ROOT="."; OUT=""; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --ir) IR="$2"; shift 2;; --root) ROOT="$2"; shift 2;; --output|-o) OUT="$2"; shift 2;; --json) JSON_OUT=1; shift;; *) echo "unknown arg: $1" >&2; exit 64;; esac; done
[[ -n "$OUT" ]] || { echo "--output required" >&2; exit 64; }
bash "$(dirname "$0")/edit_ir_validate.sh" --ir "$IR" --root "$ROOT" --json >/dev/null
source_path="$ROOT/$(jq -r '.source' "$IR")"; mkdir -p "$(dirname "$OUT")"
jq -n -j --rawfile text "$source_path" --slurpfile ir "$IR" '$ir[0].edits|sort_by(.capture.start)|reverse|reduce .[] as $e ($text; .[0:$e.capture.start]+$e.replacement+.[$e.capture.end:])' > "$OUT"
hash="$( (sha256sum "$OUT" 2>/dev/null || shasum -a 256 "$OUT")|awk '{print $1}')"
jq -n --arg output "$OUT" --arg hash "$hash" --argjson edits "$(jq '.edits|length' "$IR")" '{schema_version:"1.0",ok:true,output:$output,output_hash:$hash,edits:$edits}'
