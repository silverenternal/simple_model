#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.0 release SLO tests"
echo "==============================================="
bash generators/semantic_graph.sh --root . --struct ./struct.json --output "$tmp/semantic.json" --json >/dev/null
bash generators/score_calibrate.sh --output "$tmp/score-model.json" --json >/dev/null
bash generators/production_benchmark.sh --root . --struct ./struct.json --output-dir "$tmp/bench" --json >/dev/null
check "release slo v2 includes readiness" bash -c "bash generators/release_slo.sh --semantic-graph '$tmp/semantic.json' --score-model '$tmp/score-model.json' --production '$tmp/bench/production-scorecard.json' --json | tee '$tmp/slo.json' | jq -e '(.schema_version == \"2.0\" or .schema_version == \"2.1\" or .schema_version == \"2.2\") and .ok == true and .checks.semantic_graph == true and .checks.score_model == true and has(\"v1_readiness\")'"
check "package manifest can include v1 readiness" bash -c "mkdir -p generated/releases && cp '$tmp/slo.json' generated/releases/v1.0-readiness.json && bash tools/package_codex_plugin.sh --version 0.6.0 | jq -e '.ok == true'"
echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
