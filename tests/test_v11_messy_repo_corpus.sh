#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
pass=0; fail=0; EXIT_CODE=0
check(){ local name="$1"; shift; if "$@" >/dev/null; then echo "  [OK]   $name"; pass=$((pass+1)); else echo "  [FAIL] $name"; fail=$((fail+1)); EXIT_CODE=1; fi; }
echo "==============================================="
echo "  v1.1 messy repo corpus tests"
echo "==============================================="
check "messy corpus labels" jq -e '(.fixtures|length >= 1) and (.fixtures[0].adversarial|index("generated_client"))' benchmarks/messy-repo-corpus/labels.json
check "messy corpus fixture files" bash -c "test -f benchmarks/messy-repo-corpus/ts-python-go-monorepo/apps/web/routes.ts && test -f benchmarks/messy-repo-corpus/ts-python-go-monorepo/services/worker/jobs.py && test -f benchmarks/messy-repo-corpus/ts-python-go-monorepo/services/api/server.go"
echo "  passed: $pass"; echo "  failed: $fail"; exit $EXIT_CODE
