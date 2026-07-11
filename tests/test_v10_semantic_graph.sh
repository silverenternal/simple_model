#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.0 semantic graph tests"
echo "==============================================="
check "semantic graph schema" jq -e '.required|index("graph_hash")' specs/semantic-graph-v2.json
check "semantic graph emits stable hash" bash -c "bash generators/semantic_graph.sh --root examples/plugin-target-repo --struct examples/plugin-target-repo/struct.json --output '$tmp/semantic.json' --json | jq -e '.schema_version == \"2.0\" and (.graph_hash|length)==64 and .summary.nodes >= 1'"
check "optimization graph consumes semantic graph" bash -c "bash generators/optimization_graph.sh --root examples/plugin-target-repo --struct examples/plugin-target-repo/struct.json --output '$tmp/graph.json' --json | jq -e '.inputs.semantic_graph.nodes >= 1 and .summary.nodes >= 1'"
check "test dag carries semantic explanation" bash -c "bash generators/test_impact_dag.sh --root . --struct ./struct.json --output '$tmp/dag.json' --json | jq -e '.summary.semantic_nodes >= 1 and all(.tests[]; .explain.strategy == \"semantic-graph-domain-hybrid\")'"
echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
