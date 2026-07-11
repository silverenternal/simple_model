#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local name="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $name"; pass=$((pass+1)); else echo "  [FAIL] $name"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.1 symbol identity tests"
echo "==============================================="
check "symbol identity stable ids" bash -c "bash generators/symbol_identity.sh --root . --struct ./struct.json --output '$tmp/symbols.json' --json | jq -e '.schema_version==\"1.0\" and .summary.symbols > 0 and all(.symbols[]; .stable_id and .structural_signature and .invalidation_key != null)'"
check "symbol identity schema" jq -e '.conflict_policy == "review_required" and (.required_symbol_fields|index("stable_id"))' specs/semantic-symbol-index.json
check "plugin symbol-index command" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh symbol-index --output '$tmp/plugin-symbols.json' --json | jq -e '.summary.symbols > 0'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
