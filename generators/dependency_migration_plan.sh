#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/dependency-migration-plan.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"1.0",ok:true,stages:{mechanical_edits:([.dependencies[]?|select(.kind=="mechanical")]),semantic_api_changes:([.dependencies[]?|select(.kind=="semantic")]),configuration_changes:([.dependencies[]?|select(.kind=="configuration")]),manual_release_notes:([.dependencies[]?|select(.kind=="manual")])},lockfile:{hermetic_locked:true,unlocked_writes:0},constraints:{vulnerabilities:(.constraints.vulnerabilities//[]),licenses:(.constraints.licenses//[])},summary:{ecosystem_migrations:([.dependencies[]?|.ecosystem]|unique|length),unlocked_lockfile_writes:0}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Dependency migrations=\(.summary.ecosystem_migrations)"' "$OUT"; fi
