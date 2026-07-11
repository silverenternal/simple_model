#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.2 macro outcome ledger tests"
echo "==============================================="
check "outcome ledger hash linked" bash -c "bash generators/macro_outcome_ledger.sh --output '$tmp/ledger.json' --json | jq -e '.ok == true and .privacy.store_full_source == false and all(.entries[]; (.entry_hash|length)==64)'"
check "ledger spec privacy" jq -e '.privacy.store_full_source == false' specs/macro-outcome-ledger.json
check "plugin macro-ledger" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-ledger --output '$tmp/plugin.json' --json | jq -e '.summary.failures == 0'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
