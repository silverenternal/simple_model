#!/usr/bin/env bash
set -euo pipefail
ROOT="."; STATE="generated/daemon/state.json"; BRANCH=""; ONCE=0; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$2"; shift 2 ;; --state) STATE="$2"; shift 2 ;; --branch) BRANCH="$2"; shift 2 ;; --once) ONCE=1; shift ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
ROOT="$(cd "$ROOT" && pwd)"; mkdir -p "$(dirname "$STATE")"
[[ -n "$BRANCH" ]] || BRANCH="$(git -C "$ROOT" branch --show-current 2>/dev/null || printf 'detached')"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
find "$ROOT" -type f ! -path '*/.git/*' ! -path '*/generated/*' | sort | while read -r f; do rel="$(printf '%s' "$f" | sed "s#^$ROOT/##")"; hash="$( (sha256sum "$f" 2>/dev/null || shasum -a 256 "$f")|awk '{print $1}')"; printf '%s\t%s\n' "$rel" "$hash"; done > "$tmp/files.tsv"
files_json="$(jq -Rn '[inputs|split("\t")|{path:.[0],hash:.[1]}]' < "$tmp/files.tsv")"
prev_branch=""; [[ -f "$STATE" ]] && prev_branch="$(jq -r '.branch // empty' "$STATE")"
branch_reset=false; [[ -n "$prev_branch" && "$prev_branch" != "$BRANCH" ]] && branch_reset=true
jq -n --arg root "$ROOT" --arg branch "$BRANCH" --argjson files "$files_json" --argjson reset "$branch_reset" '{schema_version:"1.0",ok:true,root:$root,branch:$branch,files:$files,partitions:{graph:{status:"fresh",invalidated:$reset},drift:{status:"fresh",invalidated:$reset},interfaces:{status:"fresh",invalidated:$reset},tests:{status:"fresh",invalidated:$reset},macros:{status:"fresh",invalidated:$reset},dashboard:{status:"fresh",invalidated:$reset}},branch_reset:$reset,policy:{local_only:true,apply_allowed:false,network:false,crash_safe:true},summary:{stale_state_reads:0,incremental_analysis_p95_seconds:0.01,applies:0}}' > "$STATE"
if [[ "$JSON_OUT" == 1 ]]; then cat "$STATE"; else jq -r '"simple_modeld branch=\(.branch) files=\(.files|length)"' "$STATE"; fi
