#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.0 artifact cache tests"
echo "==============================================="
jq -n '{ok:true,value:1}' > "$tmp/result.json"
check "artifact cache store" bash generators/artifact_cache.sh --cache "$tmp/cache.json" --root . --command "demo" --inputs "todo.json" --result "$tmp/result.json" --store --json
check "artifact cache lookup hit" bash -c "bash generators/artifact_cache.sh --cache '$tmp/cache.json' --root . --command demo --inputs todo.json --lookup --json | jq -e '.schema_version == \"2.0\" and .hit == true and .entry.replay.stable == true'"
echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
