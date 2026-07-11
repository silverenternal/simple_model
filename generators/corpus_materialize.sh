#!/usr/bin/env bash
set -euo pipefail
MANIFEST=""; OUT_DIR="generated/benchmarks/external-corpus"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --manifest|-m) MANIFEST="$2"; shift 2 ;; --output-dir) OUT_DIR="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$MANIFEST" ]] || { echo "--manifest required" >&2; exit 64; }
mkdir -p "$OUT_DIR"
jq -c '.entries[]' "$MANIFEST" | while IFS= read -r e; do id="$(jq -r .id <<<"$e")"; jq -n --argjson e "$e" '{schema_version:"1.0",id:$e.id,repository:$e.repository,commit:$e.commit,license:$e.license,partition:$e.partition,source_retained:false,metadata_only:true}' > "$OUT_DIR/$id.json"; done
hash="$(find "$OUT_DIR" -type f -name '*.json' -print | sort | xargs cat | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
jq -n --arg hash "$hash" --argjson entries "$(jq '.entries' "$MANIFEST")" '{schema_version:"2.0",ok:true,entries:($entries|length),materialized_metadata_only:true,content_hash:$hash}' > "$OUT_DIR/manifest.json"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT_DIR/manifest.json"; else jq -r '"Corpus materialized metadata entries=\(.entries)"' "$OUT_DIR/manifest.json"; fi
