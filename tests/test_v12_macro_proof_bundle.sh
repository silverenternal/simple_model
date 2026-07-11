#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.2 macro proof bundle tests"
echo "==============================================="
check "proof bundle complete" bash -c "bash generators/macro_proof_bundle.sh --output '$tmp/proof.json' --json | jq -e '.ok == true and (.bundle_hash|length)==64 and .operator_ir and .motif_evidence and .composition and .plan_search and .rollback_manifest' && test -f '$tmp/proof.md'"
check "proof bundle spec" jq -e '.required|index("bundle_hash")' specs/macro-proof-bundle.json
check "plugin macro-proof-bundle" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-proof-bundle --output '$tmp/plugin.json' --json | jq -e '(.bundle_hash|length)==64'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
