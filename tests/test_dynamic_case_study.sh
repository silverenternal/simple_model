#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }

cd "$ROOT_DIR"
WRAP="$ROOT_DIR/codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh"

check "dynamic case study runs" bash -c "bash examples/dynamic-case-study/run.sh | jq -e '.ok == true and .discovered.dynamic_surfaces >= 8 and .discovered.observed >= 4 and .unsafe_to_automate == true'"
check "case study artifacts" bash -c "test -f generated/dynamic-case-study/case-study-report.md && test -f generated/dynamic-case-study/dynamic-surfaces.observed.json && test -f generated/dynamic-case-study/adoption/adoption-report.md"
check "plugin case study command" bash -c "'$WRAP' dynamic-case-study --json | jq -e '.ok == true and .reports.dynamic_surfaces'"
check "docs dynamic playbook" bash -c "test -f docs/playbooks/dynamic-governance.md && grep -q 'runtime-probe' docs/playbooks/dynamic-governance.md"
check "dynamic tool comparison caveat" bash -c "bash generators/competitive_scorecard.sh --json | jq -e '.caveats[]|select(test(\"external certification\"))'"

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
