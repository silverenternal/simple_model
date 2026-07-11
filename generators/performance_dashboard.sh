#!/usr/bin/env bash
set -euo pipefail

SCORECARD="generated/performance/scorecard.json"
TEST_REPORT="generated/tests/test-runner.json"
OUT="generated/performance/dashboard.html"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --scorecard) SCORECARD="$2"; shift 2 ;;
    --test-report) TEST_REPORT="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

mkdir -p "$(dirname "$OUT")"
score=$(jq '.' "$SCORECARD" 2>/dev/null || jq -n '{ok:false,benchmarks:[],summary:{}}')
tests=$(jq '.' "$TEST_REPORT" 2>/dev/null || jq -n '{ok:false,results:[],summary:{}}')
report=$(jq -n --arg output "$OUT" --argjson score "$score" --argjson tests "$tests" '{
  schema_version:"1.0", ok:true, output:$output,
  summary:{
    benchmark_ok:($score.ok // false),
    test_ok:($tests.ok // false),
    warm_seconds:($score.summary.warm_seconds // 0),
    serial_test_seconds:($score.summary.serial_test_seconds // 0),
    parallel_test_seconds:($score.summary.parallel_test_seconds // 0),
    cache_hits:($tests.summary.cached // 0),
    cache_misses:($tests.summary.ran // 0)
  },
  slowest_tests:(($tests.results // []) | sort_by(-(.duration_seconds // 0)) | .[0:10]),
  benchmarks:($score.benchmarks // [])
}')

{
  echo '<!doctype html><html><head><meta charset="utf-8"><title>simple_model Performance</title><style>body{font-family:Arial,sans-serif;margin:24px;color:#1f2937}table{border-collapse:collapse;width:100%}td,th{border:1px solid #d1d5db;padding:6px 8px;text-align:left}.ok{color:#047857}.bad{color:#b91c1c}</style></head><body>'
  echo '<h1>simple_model Performance Dashboard</h1>'
  jq -r '"<p>Benchmark: <span class=\"" + (if .summary.benchmark_ok then "ok" else "bad" end) + "\">" + (.summary.benchmark_ok|tostring) + "</span> | Test: <span class=\"" + (if .summary.test_ok then "ok" else "bad" end) + "\">" + (.summary.test_ok|tostring) + "</span></p>"' <<<"$report"
  jq -r '"<h2>Summary</h2><ul><li>warm seconds: " + (.summary.warm_seconds|tostring) + "</li><li>serial test seconds: " + (.summary.serial_test_seconds|tostring) + "</li><li>parallel test seconds: " + (.summary.parallel_test_seconds|tostring) + "</li><li>cache hits: " + (.summary.cache_hits|tostring) + "</li><li>cache misses: " + (.summary.cache_misses|tostring) + "</li></ul>"' <<<"$report"
  echo '<h2>Benchmarks</h2><table><tr><th>id</th><th>ok</th><th>seconds</th><th>hash</th></tr>'
  jq -r '.benchmarks[]? | "<tr><td>" + .id + "</td><td>" + (.ok|tostring) + "</td><td>" + (.duration_seconds|tostring) + "</td><td><code>" + .output_hash + "</code></td></tr>"' <<<"$report"
  echo '</table><h2>Slowest Tests</h2><table><tr><th>id</th><th>cached</th><th>seconds</th><th>exit</th></tr>'
  jq -r '.slowest_tests[]? | "<tr><td>" + .id + "</td><td>" + (.cached|tostring) + "</td><td>" + (.duration_seconds|tostring) + "</td><td>" + (.exit_code|tostring) + "</td></tr>"' <<<"$report"
  echo '</table></body></html>'
} > "$OUT"

if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Performance Dashboard: " + .output' <<<"$report"; fi
