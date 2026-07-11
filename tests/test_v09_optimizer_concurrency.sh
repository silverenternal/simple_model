#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
echo "==============================================="
echo "  v0.9 optimizer concurrency tests"
echo "==============================================="

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

check "optimization graph emits stable hash" bash generators/optimization_graph.sh --root . --struct ./struct.json --output "$tmp/graph.json" --json
check "graph has components and macro candidates" jq -e '.ok == true and (.graph_hash|length)==64 and .summary.components > 0 and .summary.macro_candidates >= 1' "$tmp/graph.json"
check "graph nodes have hashes and evidence" jq -e 'all(.nodes[]; (.id|length)>0 and (.hash|length)>0 and (.evidence.source|length)>0)' "$tmp/graph.json"

check "optimizer search emits decision trace" bash generators/optimizer_search.sh --graph "$tmp/graph.json" --output "$tmp/search.json" --budget 2 --json
check "search selected candidates and stop reason" jq -e '.ok == true and .summary.candidates >= 1 and (.decision_trace|length) == .summary.candidates and (.stop_reason|length)>0' "$tmp/search.json"

check "score proof emits bounded summary" bash generators/score_delta_proof.sh --search "$tmp/search.json" --output "$tmp/proof.json" --json
check "score proof is reproducible summary" jq -e '.ok == true and (.proof_hash|length)>0 and .summary.selected >= 1 and .conclusion == "non_regressing"' "$tmp/proof.json"

check "autopilot v2 connects graph search simulation and tests" bash generators/autopilot.sh --root . --struct ./struct.json --output-dir "$tmp/autopilot" --jobs 2 --budget 2 --mode fast --json
check "autopilot v2 report" jq -e '.schema_version == "2.0" and .ok == true and (.graph_hash|length)==64 and .phases.search.selected >= 1 and .phases.tests.failed == 0 and .parallel_tasks.jobs == 2' "$tmp/autopilot/autopilot.json"

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
