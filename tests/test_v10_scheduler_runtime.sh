#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
echo "==============================================="
echo "  v1.0 scheduler runtime tests"
echo "==============================================="
jq -n '{tasks:[{id:"a",command:"true",cwd:".",inputs:[],outputs:[],deps:[],timeout:5,resource:"io",cache:false}]}' > "$tmp/tasks.json"
check "scheduler run schema" jq -e '.properties.schema_version.const == "2.0"' specs/scheduler-run.json
check "scheduler v2 runtime fields" bash -c "bash generators/parallel_scheduler.sh --tasks '$tmp/tasks.json' --output '$tmp/run.json' --jobs 2 --retries 1 --json | jq -e '.schema_version == \"2.0\" and .runtime.retries == 1 and (.runtime.resource_classes|index(\"io\")) != null'"
check "scheduler cancellation file fails closed" bash -c "touch '$tmp/cancel' && ! bash generators/parallel_scheduler.sh --tasks '$tmp/tasks.json' --output '$tmp/cancel-run.json' --cancel-file '$tmp/cancel' --json >/dev/null"
echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
