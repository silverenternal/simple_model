#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local name="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $name"; pass=$((pass+1)); else echo "  [FAIL] $name"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.1 incremental semantic graph tests"
echo "==============================================="
check "incremental graph emits diff" bash -c "bash generators/semantic_graph_incremental.sh --root . --struct ./struct.json --output '$tmp/graph.json' --diff-output '$tmp/diff.json' --cache '$tmp/cache.json' --json | jq -e '.graph.schema_version==\"2.1\" and .diff.schema_version==\"1.0\" and .graph.parser_tiers.files > 0'"
check "second incremental graph cache hit" bash -c "bash generators/semantic_graph_incremental.sh --root . --struct ./struct.json --output '$tmp/graph.json' --diff-output '$tmp/diff.json' --cache '$tmp/cache.json' --json | jq -e '.diff.cache_hit == true'"
check "plugin semantic-graph-incremental command" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh semantic-graph-incremental --output '$tmp/plugin-graph.json' --diff-output '$tmp/plugin-diff.json' --json | jq -e '.graph.summary.nodes > 0'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
