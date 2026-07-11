#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local name="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $name"; pass=$((pass+1)); else echo "  [FAIL] $name"; fail=$((fail+1)); EXIT_CODE=1; fi; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.1 language-native codemod tests"
echo "==============================================="
mkdir -p "$tmp/repo"; printf '{"a":1}\n' > "$tmp/repo/config.json"; printf '{"idempotency_key":"k","edits":[{"path":"config.json","op":"json_set","key":"b","value":2}]}\n' > "$tmp/spec.json"
check "adapter metadata exists" bash -c "jq -e '.tier != \"review_only\"' codemods/adapters/python.json && jq -e '.operations|index(\"json_set\")' codemods/adapters/config.json"
check "codemod backend adapter dispatch" bash -c "bash generators/codemod_backend.sh --root '$tmp/repo' --spec '$tmp/spec.json' --output '$tmp/result.json' --simulate --json | jq -e '.schema_version==\"1.1\" and .backend.adapter_dispatch == true and (.summary.adapters|index(\"config\"))'"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
