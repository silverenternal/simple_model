#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/normalized-findings.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$INPUT" ]] || { echo "--input is required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '
  def raw_hash: (tojson|@base64);
  [ .[] | . as $f | {schema_version:"1.0",semantic_id:($f.semantic_id // (($f.category//"unknown")+":"+($f.path // ($f.location.path//""))+":"+($f.rule_id//"unknown")+":"+($f.symbol_id//""))),category:($f.category//"unknown"),severity:($f.severity//"warning"),message:($f.message//""),location:($f.location // {path:($f.path//"unknown"),line:($f.line//0)}),evidence:($f.evidence//{}),provenance:[{tool:($f.tool//"unknown"),rule_id:($f.rule_id//"unknown"),raw_hash:($f|raw_hash)}]} ]
  | group_by(.semantic_id)
  | map(.[0] + {provenance:([.[].provenance[]]|unique_by([.tool,.rule_id,.raw_hash])|sort_by(.tool,.rule_id)),tools:([.[].provenance[].tool]|unique|sort),evidence_count:length})
  | sort_by(.semantic_id)
  | {schema_version:"1.0",ok:true,findings:.,summary:{input_findings:([.[]|.evidence_count]|add//0),normalized:length,deduplicated:(([.[]|.evidence_count]|add//0)-length),provenance_loss:0}}
' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Normalized findings=\(.summary.normalized) deduplicated=\(.summary.deduplicated)"' "$OUT"; fi
