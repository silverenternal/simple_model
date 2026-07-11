#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }

cd "$ROOT_DIR"
TARGET="$ROOT_DIR/examples/dynamic-case-study/target"
STRUCT="$TARGET/struct.json"
WRAP="$ROOT_DIR/codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh"

check "runtime probe dry-run plan" bash -c "bash generators/runtime_probe.sh --root '$TARGET' --output '$TMP_DIR/probe-plan.json' --json | jq -e '.mode == \"plan\" and .summary.probes == 1 and .summary.executed == 0'"
check "runtime probe execute observations" bash -c "bash generators/runtime_probe.sh --root '$TARGET' --execute --output '$TMP_DIR/observations.json' --json | jq -e '.mode == \"execute\" and .summary.executed == 1 and .summary.observations >= 4 and all(.observations[]; .hash)'"
check "runtime probe rejects unlisted command" bash -c "mkdir -p '$TMP_DIR/bad/.simple_model' && jq -n '{schema_version:\"1.0\", allowed_commands:[], probes:[{id:\"bad\", command:\"bash scripts/probe.sh\", cwd:\".\", parser:\"json-lines\"}]}' > '$TMP_DIR/bad/.simple_model/probes.json' && bash generators/runtime_probe.sh --root '$TMP_DIR/bad' --execute --json | jq -e '.ok == false and .summary.denied == 1'"
check "dynamic observation merge observes nodes" bash -c "bash generators/dynamic_surface_scan.sh --root '$TARGET' --struct '$STRUCT' --output '$TMP_DIR/surfaces.json' --json >/dev/null && bash generators/dynamic_observation_merge.sh --surfaces '$TMP_DIR/surfaces.json' --observations '$TMP_DIR/observations.json' --output '$TMP_DIR/merged.json' --json | jq -e '.summary.observed >= 4 and .summary.probe_gaps >= 1 and .contract_hash'"
check "plugin runtime-probe command" bash -c "'$WRAP' --target-root '$TARGET' runtime-probe --execute --output '$TMP_DIR/wrap-observations.json' --json | jq -e '.summary.observations >= 4'"
check "plugin dynamic-merge command" bash -c "'$WRAP' dynamic-merge --surfaces '$TMP_DIR/surfaces.json' --observations '$TMP_DIR/observations.json' --output '$TMP_DIR/wrap-merged.json' --json | jq -e '.summary.observed >= 4'"

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
