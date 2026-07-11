#!/usr/bin/env bash
set -euo pipefail
IR=""; ROOT="."; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --ir) IR="$2"; shift 2;; --root) ROOT="$2"; shift 2;; --json) JSON_OUT=1; shift;; *) echo "unknown arg: $1" >&2; exit 64;; esac; done
[[ -f "$IR" ]] || { echo "--ir required" >&2; exit 64; }
source_path="$ROOT/$(jq -r '.source' "$IR")"; [[ -f "$source_path" ]] || { echo "source missing: $source_path" >&2; exit 2; }
actual_hash="$( (sha256sum "$source_path" 2>/dev/null || shasum -a 256 "$source_path") | awk '{print $1}')"
report="$(jq -n --rawfile text "$source_path" --slurpfile ir "$IR" --arg actual_hash "$actual_hash" '
  ($ir[0]) as $ir | ($ir.edits|sort_by(.capture.start,.capture.end)) as $edits
  | ([range(0;($edits|length)-1) as $i | select($edits[$i].capture.end > $edits[$i+1].capture.start) | {left:$edits[$i].id,right:$edits[$i+1].id,start:$edits[$i+1].capture.start}] ) as $overlaps
  | ([$edits[] | select(.capture.start>.capture.end or ($text[.capture.start:.capture.end] != .original)) | {id,start:.capture.start,end:.capture.end,actual:$text[.capture.start:.capture.end],expected:.original}]) as $stale
  | {schema_version:"1.0",ok:(($actual_hash==$ir.source_hash) and ($overlaps|length==0) and ($stale|length==0)),source:$ir.source,hash_match:($actual_hash==$ir.source_hash),overlaps:$overlaps,stale_captures:$stale,summary:{edits:($edits|length),overlaps:($overlaps|length),stale:($stale|length)}}')"
printf '%s\n' "$report"
[[ "$(jq -r .ok <<<"$report")" == true ]] || exit 3
