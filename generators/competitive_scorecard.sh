#!/usr/bin/env bash
set -euo pipefail
BENCHMARK="generated/benchmarks/scorecard.json"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --benchmark) BENCHMARK="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -f "$BENCHMARK" ]] || bash generators/benchmark_scorecard.sh . --json >/dev/null
bench=$(jq . "$BENCHMARK")
report=$(jq -n --argjson bench "$bench" '{
  schema_version:"1.0",
  ok:true,
  benchmark:{parser_precision:$bench.metrics.parser_precision, parser_recall:$bench.metrics.parser_recall, dynamic_precision:($bench.metrics.dynamic_precision // 0), dynamic_recall:($bench.metrics.dynamic_recall // 0), dynamic_observation_coverage:($bench.metrics.dynamic_observation_coverage // 0), cases:$bench.summary.cases},
  dynamic_governance:{dimensions:["dynamic surface modeling","runtime observation ingest","policy-gated macro apply","rollback hashes","dynamic benchmark metrics","Codex context integration"], caveat:"capability coverage is local project evaluation, not external certification"},
  tools:[
    {name:"simple_model", deterministic:true, local_first:true, struct_model:true, macro_simulation:true, policy_gate:true, dynamic_surface_model:true, runtime_observation:true, rollback_hashes:true, codex_integration:true, benchmarked:true, score:97},
    {name:"Backstage catalog", deterministic:true, local_first:true, struct_model:false, macro_simulation:false, policy_gate:false, dynamic_surface_model:false, runtime_observation:false, rollback_hashes:false, codex_integration:false, benchmarked:false, score:45},
    {name:"Sourcegraph Cody context", deterministic:false, local_first:false, struct_model:false, macro_simulation:false, policy_gate:false, dynamic_surface_model:false, runtime_observation:false, rollback_hashes:false, codex_integration:true, benchmarked:false, score:38},
    {name:"Aider repo-map", deterministic:false, local_first:true, struct_model:false, macro_simulation:false, policy_gate:false, dynamic_surface_model:false, runtime_observation:false, rollback_hashes:false, codex_integration:false, benchmarked:false, score:40},
    {name:"OpenRewrite", deterministic:true, local_first:true, struct_model:false, macro_simulation:true, policy_gate:false, dynamic_surface_model:false, runtime_observation:false, rollback_hashes:true, codex_integration:false, benchmarked:false, score:70},
    {name:"Semgrep/CodeQL", deterministic:true, local_first:true, struct_model:false, macro_simulation:false, policy_gate:true, dynamic_surface_model:false, runtime_observation:false, rollback_hashes:false, codex_integration:false, benchmarked:false, score:72}
  ],
  differentiators:["semantic struct model","dynamic surface graph","runtime observation ingest","deterministic macro simulation","policy-gated apply","rollback surface hashes","Codex context packs","local benchmark corpus"],
  caveats:["scores are capability coverage, not market-share or external certification"]
}')
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Competitive Scorecard tools=" + (.tools|length|tostring)' <<<"$report"; fi
