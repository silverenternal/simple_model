#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }

cd "$ROOT_DIR"
TARGET="$ROOT_DIR/examples/dynamic-case-study/target"
STRUCT="$TARGET/struct.json"

check "dynamic benchmark corpus expanded" bash -c "jq -e '(.cases|length) >= 30 and ([.cases[]|select((.dynamic // [])|length > 0)]|length) >= 10' benchmarks/semantic-plugin-corpus/corpus.json"
check "benchmark dynamic metrics" bash -c "bash generators/benchmark_scorecard.sh . --json | jq -e '.schema_version == \"2.0\" and .ok == true and .summary.cases >= 30 and .metrics.dynamic_precision >= .thresholds.dynamic_precision and .metrics.dynamic_recall >= .thresholds.dynamic_recall and .metrics.dynamic_unsafe_detection_rate >= .thresholds.dynamic_unsafe_detection_rate'"
check "release slo dynamic checks" bash -c "bash generators/release_slo.sh --json | jq -e '.ok == true and .checks.dynamic_precision == true and .checks.dynamic_recall == true and .checks.dynamic_unsafe_detection_rate == true'"
check "adoption report dynamic section" bash -c "bash generators/adoption_report.sh --root '$TARGET' --struct '$STRUCT' --output-dir '$TMP_DIR/adoption' --json | jq -e '.dynamic.summary.nodes >= 8 and .benchmark.dynamic_precision >= 0.8 and .policy_readiness.ready == false'"
check "context pack dynamic evidence" bash -c "bash generators/codex_context_pack.sh --root '$TARGET' --struct '$STRUCT' --workflow macro-authoring --output-dir '$TMP_DIR/context' --json | jq -e '.dynamic_evidence.summary.nodes >= 8 and (.forbidden_macro_actions|length) >= 1 and .omitted.dynamic_risks >= 1'"
check "competitive scorecard dynamic dimensions" bash -c "bash generators/competitive_scorecard.sh --benchmark generated/benchmarks/scorecard.json --json | jq -e '. as \$root | (\$root.dynamic_governance.dimensions|index(\"runtime observation ingest\")) and (\$root.tools[]|select(.name==\"simple_model\" and .dynamic_surface_model==true and .runtime_observation==true))'"

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
