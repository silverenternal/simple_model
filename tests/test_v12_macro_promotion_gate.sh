#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.2 macro promotion tests"
echo "==============================================="
check "promotion gate records evidence" bash -c "bash generators/macro_promotion_gate.sh --output '$tmp/promotion.json' --json | jq -e '.ok == true and all(.decisions[]; .evidence.proof_bundle_hash and .manifest_entry.proof_bundle_hash)'"
check "promotion spec evidence" jq -e '.required_evidence|index("proof_bundle")' specs/macro-promotion.json
check "plugin macro-promotion" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-promotion --output '$tmp/plugin.json' --json | jq -e '.summary.templates >= 0'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
