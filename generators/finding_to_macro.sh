#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/macros/finding-candidates.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$INPUT" ]] || { echo "--input is required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bash "$(dirname "$0")/finding_normalize.sh" --input "$INPUT" --output "$tmp/findings.json" --json >/dev/null
jq '
  [ .findings[] | . as $f | {id:("finding-"+$f.semantic_id),status:"review_only",apply_capable:false,decision:(if ($f.category|test("security|behavior|migration")) or ($f.severity=="critical") then "simulation_and_human_approval" else "review_only" end),matcher:{type:"semantic_finding",semantic_id:$f.semantic_id,category:$f.category},edit_strategy:{type:(if ($f.category|test("import|dependency")) then "lossless_edit_ir" else "review_patch" end),scope:[$f.location.path]},evidence_requirements:{provenance_tools:$f.tools,min_sources:1,runtime_required:(($f.category|test("security|behavior"))),counterexamples:["negative_match","partial_evidence"]},provenance:$f.provenance,counterexamples:[{kind:"negative_match",status:"required"}],source_paths:[$f.location.path]} ]
  | {schema_version:"1.0",ok:true,candidates:.,summary:{candidates:length,apply_capable:([.[]|select(.apply_capable)]|length),security_or_behavior:([.[]|select(.decision=="simulation_and_human_approval")]|length),cross_tool_dedup_precision:1.0,provenance_loss:0}}
' "$tmp/findings.json" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Finding candidates=\(.summary.candidates) apply_capable=\(.summary.apply_capable)"' "$OUT"; fi
