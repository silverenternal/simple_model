#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$ROOT_DIR/examples/dynamic-case-study/target"
OUT="$ROOT_DIR/generated/dynamic-case-study"
STRUCT="$TARGET/struct.json"
mkdir -p "$OUT"

surfaces=$(bash "$ROOT_DIR/generators/dynamic_surface_scan.sh" --root "$TARGET" --struct "$STRUCT" --output "$OUT/dynamic-surfaces.json" --json)
probe_plan=$(bash "$ROOT_DIR/generators/runtime_probe.sh" --root "$TARGET" --output "$OUT/runtime-probe-plan.json" --json)
observations=$(bash "$ROOT_DIR/generators/runtime_probe.sh" --root "$TARGET" --execute --output "$OUT/runtime-observations.json" --json)
merged=$(bash "$ROOT_DIR/generators/dynamic_observation_merge.sh" --surfaces "$OUT/dynamic-surfaces.json" --observations "$OUT/runtime-observations.json" --output "$OUT/dynamic-surfaces.observed.json" --json)
adoption=$(bash "$ROOT_DIR/generators/adoption_report.sh" --root "$TARGET" --struct "$STRUCT" --output-dir "$OUT/adoption" --json)
benchmark=$(bash "$ROOT_DIR/generators/benchmark_scorecard.sh" "$ROOT_DIR" --json)
plan="$OUT/macro-plan.json"
jq -n --arg root "$TARGET" --arg struct "$STRUCT" '{
  schema_version:"1.0",
  ok:true,
  root:$root,
  struct:$struct,
  actions:[{
    id:"case-study.review-dynamic-plugin-loader",
    macro_id:"normalize_component_exports",
    risk:"medium",
    execution_tier:"safe_codemod",
    auto_apply:false,
    target:{component:"Plugins", path:"src/plugins.ts", struct:$struct},
    writes:["src/plugins.ts"],
    policy:{simulation_required:true, policy_required:true},
    dynamic:{missing_observations:["dynamic import"], unsafe_nodes:["prototype mutation"]}
  }]
}' > "$plan"
simulation=$(bash "$ROOT_DIR/generators/macro_simulate.sh" --plan "$plan" --output-dir "$OUT/optimization" --json || true)
policy=$(bash "$ROOT_DIR/generators/policy_eval.sh" --plan "$plan" --dynamic "$OUT/dynamic-surfaces.observed.json" --simulation "$OUT/optimization/simulation.json" --json || true)

report=$(jq -n \
  --arg target "$TARGET" \
  --arg out "$OUT" \
  --argjson surfaces "$surfaces" \
  --argjson probe_plan "$probe_plan" \
  --argjson observations "$observations" \
  --argjson merged "$merged" \
  --argjson adoption "$adoption" \
  --argjson benchmark "$benchmark" \
  --argjson simulation "$simulation" \
  --argjson policy "$policy" '{
    ok:true,
    target:$target,
    output:$out,
    discovered:{
      dynamic_surfaces:$surfaces.summary.nodes,
      unsafe:$surfaces.summary.dynamic_unsafe,
      observed:$merged.summary.observed,
      probe_gaps:$merged.summary.probe_gaps
    },
    safe_to_automate:($policy.decision == "allow"),
    unsafe_to_automate:($policy.decision == "deny"),
    reports:{
      dynamic_surfaces:"dynamic-surfaces.json",
      runtime_observations:"runtime-observations.json",
      merged_dynamic_surfaces:"dynamic-surfaces.observed.json",
      adoption:"adoption/adoption-report.md",
      benchmark:"../../generated/benchmarks/scorecard.json",
      simulation:"optimization/simulation.json"
    },
    phases:{probe_plan:$probe_plan.summary, observations:$observations.summary, adoption_dynamic:$adoption.dynamic.summary, benchmark_dynamic:$benchmark.metrics, simulation:$simulation.summary, policy:{decision:$policy.decision, denied:$policy.summary.denied}}
  }')
printf '%s\n' "$report" > "$OUT/case-study-report.json"
{
  echo "# Dynamic Governance Case Study Report"
  echo
  jq -r '"- dynamic surfaces: " + (.discovered.dynamic_surfaces|tostring), "- unsafe surfaces: " + (.discovered.unsafe|tostring), "- observed surfaces: " + (.discovered.observed|tostring), "- probe gaps: " + (.discovered.probe_gaps|tostring), "- safe to automate: " + (.safe_to_automate|tostring)' <<<"$report"
} > "$OUT/case-study-report.md"
printf '%s\n' "$report"
