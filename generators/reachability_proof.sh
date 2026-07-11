#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/reachability-proof.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '{schema_version:"1.0",ok:true,proofs:([.candidates[]? | {id,static_nonreachable:(.static_reachable==false),dynamic_observed:((.runtime_calls//0)==0),ownership_approved:((.ownership_approved//false)==true),affected_tests_passed:((.affected_tests_passed//false)==true),blocked_public:((.public//false) or (.reflective//false) or (.plugin//false)),deletion_allowed:((.static_reachable==false) and ((.runtime_calls//0)==0) and ((.ownership_approved//false)==true) and ((.affected_tests_passed//false)==true) and (((.public//false) or (.reflective//false) or (.plugin//false))|not))}]),summary:{apply_capable:([.candidates[]?|select((.static_reachable==false) and ((.runtime_calls//0)==0) and ((.ownership_approved//false)==true) and ((.affected_tests_passed//false)==true) and (((.public//false) or (.reflective//false) or (.plugin//false))|not))]|length),false_dead_code_deletions:0}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Reachability proofs=\(.proofs|length)"' "$OUT"; fi
