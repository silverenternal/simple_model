#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.0 framework resolver tests"
echo "==============================================="
check "framework resolver pack generates common frameworks" bash -c "bash generators/framework_resolver_pack.sh --output-dir '$tmp/resolvers' --json | jq -e '.summary.frameworks >= 10'"
check "nextjs resolver metadata" jq -e '.safety.fail_closed == true and (.patterns|index("routes")) != null' "$tmp/resolvers/nextjs.json"
check "kubernetes resolver metadata" jq -e '(.patterns|index("generated_artifacts")) != null' "$tmp/resolvers/kubernetes.json"
echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
