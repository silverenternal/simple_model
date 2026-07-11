#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
OUT="generated/adoption-report"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --output-dir) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
mkdir -p "$OUT"
ROOT="$(cd "$ROOT" && pwd)"
audit=$(bash "$SELF_DIR/adoption_audit.sh" --root "$ROOT" --struct "$STRUCT" --json || true)
ir=$(bash "$SELF_DIR/semantic_interface_ir.sh" --root "$ROOT" --struct "$STRUCT" --output "$OUT/interface-ir.json" --json || true)
score=$(bash "$SELF_DIR/optimization_score.sh" --root "$ROOT" --struct "$STRUCT" --output-dir "$OUT" --json || true)
bench=$(bash "$SELF_DIR/benchmark_scorecard.sh" . --json || true)
comp=$(bash "$SELF_DIR/competitive_scorecard.sh" --benchmark generated/benchmarks/scorecard.json --json || true)
dynamic=$(bash "$SELF_DIR/dynamic_surface_scan.sh" --root "$ROOT" --struct "$STRUCT" --output "$OUT/dynamic-surfaces.json" --json || jq -n '{nodes:[],summary:{nodes:0}}')
perf='{}'
[[ -f generated/performance/scorecard.json ]] && perf=$(jq . generated/performance/scorecard.json)
dashboard=""
[[ -f generated/performance/dashboard.html ]] && dashboard="generated/performance/dashboard.html"
report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --arg dashboard "$dashboard" --argjson audit "$audit" --argjson ir "$ir" --argjson score "$score" --argjson bench "$bench" --argjson comp "$comp" --argjson dynamic "$dynamic" --argjson perf "$perf" '{
  schema_version:"1.0",
  ok:true,
  root:$root,
  struct:$struct,
  adoption:{
    unmanaged_files:($audit.unmanaged_files // 0),
    unmanaged:($audit.unmanaged // []),
    generated_files:($dynamic.summary.generated_files // 0),
    source_contract_drift:(($dynamic.nodes // []) | map(select(.kind!="generated_interface" and .verification_status=="probe_gap"))),
    generated_code_drift:(($dynamic.nodes // []) | map(select(.kind=="generated_interface" and .verification_status=="probe_gap")))
  },
  semantic_ir:$ir.summary,
  dynamic:{
    summary:$dynamic.summary,
    by_risk:($dynamic.nodes | group_by(.risk_level) | map({risk_level:.[0].risk_level, count:length, nodes:map({id,kind,name,path,line,verification_status})})),
    unobserved:($dynamic.nodes | map(select(.verification_status=="probe_gap"))),
    probe_recommendations:($dynamic.probe_recommendations // [])
  },
  score:{score:$score.score,debt:$score.debt,factors:$score.factors},
  benchmark:{
    cases:($bench.summary.cases // 0),
    parser_precision:($bench.metrics.parser_precision // 0),
    parser_recall:($bench.metrics.parser_recall // 0),
    dynamic_precision:($bench.metrics.dynamic_precision // 0),
    dynamic_recall:($bench.metrics.dynamic_recall // 0),
    dynamic_observation_coverage:($bench.metrics.dynamic_observation_coverage // 0)
  },
  competitive:{tools:($comp.tools|length), differentiators:$comp.differentiators, dynamic_governance:($comp.dynamic_governance // {})},
  policy_readiness:{dynamic_unsafe:(($dynamic.nodes // [])|map(select(.risk_level=="dynamic_unsafe"))|length), ready:((($dynamic.nodes // [])|map(select(.risk_level=="dynamic_unsafe"))|length)==0)},
  performance:{dashboard:$dashboard, summary:($perf.summary // {})},
  next_actions:["review unmanaged files","run dynamic-surface scan","run runtime-probe --execute for probe gaps","run macro_simulate before apply","attach adoption-report.md to review"]
}')
printf '%s\n' "$report" > "$OUT/adoption-report.json"
{ echo "# simple_model Adoption Report"; echo; jq -r '"- root: " + .root, "- score: " + (.score.score|tostring), "- unmanaged files: " + (.adoption.unmanaged_files|tostring), "- semantic nodes: " + (.semantic_ir.nodes|tostring), "- dynamic surfaces: " + (.dynamic.summary.nodes|tostring), "- dynamic unsafe: " + (.dynamic.summary.dynamic_unsafe|tostring), "- dynamic unverified: " + (.dynamic.summary.dynamic_unverified|tostring), "- benchmark cases: " + (.benchmark.cases|tostring), "- dynamic precision: " + (.benchmark.dynamic_precision|tostring), "- dynamic recall: " + (.benchmark.dynamic_recall|tostring), "- performance dashboard: " + (if .performance.dashboard == "" then "not generated" else .performance.dashboard end)' <<<"$report"; echo; echo "## Dynamic Probe Recommendations"; jq -r '.dynamic.probe_recommendations[]? | "- " + .node_id + ": " + .command' <<<"$report"; echo; echo "## Next Actions"; jq -r '.next_actions[] | "- " + .' <<<"$report"; } > "$OUT/adoption-report.md"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else cat "$OUT/adoption-report.md"; fi
