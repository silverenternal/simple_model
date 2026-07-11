#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{contract_id:"api-health",observations:[{environment:"staging",build:"a",commit:"1",route:"/health",event:"ok",error_shape:"none",side_effects:[],latency_ms:10},{environment:"production",build:"b",commit:"2",route:"/health",event:"ok",error_shape:"none",side_effects:[],latency_ms:20}]}' > "$tmp/mine.json"
bash generators/runtime_contract_mine.sh --input "$tmp/mine.json" --output "$tmp/contract.json" --json >/dev/null
jq -e '.status=="reviewed" and .summary.environments==2 and (.normalization.ignored_fields|index("latency_ms"))' "$tmp/contract.json" >/dev/null
jq -n '{before:{route:"/health",event:"ok",latency_ms:10,host:"a"},after:{route:"/health",event:"ok",latency_ms:20,host:"b"},normalization:{ignored_fields:["latency_ms","host"]}}' > "$tmp/same.json"
bash generators/differential_runtime_verify.sh --input "$tmp/same.json" --output "$tmp/same-report.json" --json >/dev/null
jq -e '.equivalent and .timing_noise_only and .promotion_allowed and .summary.unexplained_runtime_divergence==0' "$tmp/same-report.json" >/dev/null
jq -n '{before:{route:"/health",event:"ok"},after:{route:"/health",event:"error"},normalization:{ignored_fields:["latency_ms"]}}' > "$tmp/diff.json"
bash generators/differential_runtime_verify.sh --input "$tmp/diff.json" --output "$tmp/diff-report.json" --json >/dev/null
jq -e '.equivalent==false and .promotion_allowed==false and (.minimized_counterexample.input_hash|length)>0 and .summary.unexplained_runtime_divergence==1' "$tmp/diff-report.json" >/dev/null
jq -e '.thresholds.noise_false_positive_rate_max<=0.02' benchmarks/runtime-differential/fixtures.json >/dev/null
echo "  [OK] runtime contract provisional/multi-env differential noise vs semantic"
