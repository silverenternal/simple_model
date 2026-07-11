#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.0 runtime contract tests"
echo "==============================================="
bash generators/dynamic_surface_scan.sh --root examples/dynamic-case-study/target --struct examples/dynamic-case-study/target/struct.json --output "$tmp/dynamic.json" --json >/dev/null
check "runtime contract schema" jq -e '.properties.contracts.items.required|index("secrets_policy")' specs/dynamic-runtime-contract.json
check "runtime contracts generated" bash -c "bash generators/runtime_contracts.sh --surfaces '$tmp/dynamic.json' --output '$tmp/contracts.json' --json | jq -e '.ok == true and .summary.contracts >= 1 and all(.contracts[]; .secrets_policy == \"deny\" and .network_policy == \"deny\")'"
echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
