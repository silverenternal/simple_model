#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.0 deep parser tests"
echo "==============================================="
check "tree sitter scan structural facts" bash -c "bash generators/tree_sitter_scan.sh --root examples/plugin-target-repo --output '$tmp/tree.json' --json | jq -e '.ok == true and .summary.symbols >= 1 and all(.facts[]; .confidence and .evidence.source)'"
check "lsp symbol index safe discovery" bash -c "bash generators/lsp_symbol_index.sh --root . --output '$tmp/lsp.json' --json | jq -e '.ok == true and .mode == \"safe-discovery\" and (.servers|type==\"object\")'"
check "plugin deep parser commands" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root examples/plugin-target-repo tree-sitter-scan --output '$tmp/wrap-tree.json' --json | jq -e '.summary.facts >= 1'"
echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
