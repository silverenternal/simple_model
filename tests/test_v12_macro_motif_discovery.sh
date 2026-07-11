#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.2 macro motif discovery tests"
echo "==============================================="
check "motif discovery emits evidence" bash -c "bash generators/macro_discover_motifs.sh --output '$tmp/motifs.json' --json | jq -e '.ok == true and .summary.candidates >= 0 and all(.candidates[]?; .graph_path and .missing_proof and .apply_capable == false)'"
check "plugin macro-motifs" bash -c "codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-motifs --output '$tmp/plugin.json' --json | jq -e '.policy.low_confidence_never_apply == true'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
