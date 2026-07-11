#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.0 codemod backend tests"
echo "==============================================="
printf '{"a":1}\n' > "$tmp/a.json"
jq -n --arg p "${tmp#/}/a.json" '{id:"demo",idempotency_key:"demo-key-123",edits:[{path:$p,op:"json_set",key:"b",value:2}]}' > "$tmp/spec.json"
check "codemod backend simulate" bash -c "bash generators/codemod_backend.sh --root / --spec '$tmp/spec.json' --output '$tmp/result.json' --simulate --json | jq -e '.ok == true and .summary.changed == 1 and (.rollback_manifest.files|length)==1'"
check "macro contract v3 requires idempotency" jq -e '(.required|index("idempotency_key")) and (.required|index("rollback")) and (.required|index("affected_tests"))' macros/macro-contract-v3.schema.json
check "repair macro packs exist" jq -e '.safety.requires_idempotency == true and (.macros|length)>=2' macros/packs/boundary-repair/pack.json
check "framework repair macro pack dynamic policy" jq -e '.safety.requires_runtime_contract_for_dynamic_apply == true' macros/packs/framework-repair/pack.json
echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
