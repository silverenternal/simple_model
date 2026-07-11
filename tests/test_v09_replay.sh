#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
echo "==============================================="
echo "  v0.9 replay tests"
echo "==============================================="

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
check "run log starts" bash generators/run_log.sh --run-dir "$tmp/run" --start --json
check "run log appends decisions" bash generators/run_log.sh --run-dir "$tmp/run" --append --event '{"event":"test","input_hash":"abc","output_hash":"def","cache":"miss"}' --json
jq -n '{ok:true, summary:{demo:1}}' > "$tmp/report.json"
check "run log finalizes summary" bash generators/run_log.sh --run-dir "$tmp/run" --finalize --report "$tmp/report.json" --json
check "run log replay verifies hash" bash generators/run_log.sh --run-dir "$tmp/run" --replay --json
check "summary is cbom-compatible enough for deterministic replay" jq -e '.ok == true and (.event_hash|length)>0 and (.report_hash|length)>0 and .summary.events == 1' "$tmp/run/summary.json"

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
