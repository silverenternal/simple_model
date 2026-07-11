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

bash generators/dynamic_surface_scan.sh --root "$TARGET" --struct "$STRUCT" --output "$TMP_DIR/surfaces.json" --json >/dev/null
cat > "$TMP_DIR/plan.json" <<JSON
{"schema_version":"1.0","root":"$TARGET","struct":"$STRUCT","actions":[{"id":"dyn.patch","macro_id":"normalize_component_exports","risk":"medium","execution_tier":"safe_codemod","auto_apply":true,"target":{"component":"Plugins","path":"src/plugins.ts"},"writes":["src/plugins.ts"],"policy":{"simulation_required":false,"policy_required":true}}]}
JSON
cat > "$TMP_DIR/observed.json" <<JSON
{"schema_version":"1.0","ok":true,"summary":{"probes":1,"executed":1,"observations":1},"observations":[{"kind":"dynamic_import","name":"<dynamic-expression>","path":"src/plugins.ts","source":"test","hash":"abc"}]}
JSON
bash generators/dynamic_observation_merge.sh --surfaces "$TMP_DIR/surfaces.json" --observations "$TMP_DIR/observed.json" --output "$TMP_DIR/merged.json" --json >/dev/null

check "policy denies unobserved unsafe dynamic apply" bash -c "! bash generators/policy_eval.sh --plan '$TMP_DIR/plan.json' --dynamic '$TMP_DIR/surfaces.json' --json"
check "policy explains dynamic requirement" bash -c "(bash generators/policy_eval.sh --plan '$TMP_DIR/plan.json' --dynamic '$TMP_DIR/surfaces.json' --json || true) | jq -e '.decision == \"deny\" and (.required_actions|length) >= 1 and (.deny[]|select(.surface_risk==\"dynamic_unsafe\"))'"
check "macro simulate reports dynamic affected nodes" bash -c "(bash generators/macro_simulate.sh --plan '$TMP_DIR/plan.json' --output-dir '$TMP_DIR/opt' --json || true) | jq -e '(.dynamic.affected_nodes|type)==\"array\" and (.dynamic.missing_observations|type)==\"array\"'"
check "macro exec apply refuses dynamic unsafe" bash -c "! bash generators/macro_exec.sh --plan '$TMP_DIR/plan.json' --apply --output-dir '$TMP_DIR/apply' --json"
check "autofix marks dynamic candidates review-only" bash -c "jq '.actions[0].dynamic={missing_observations:[\"x\"],unsafe_nodes:[\"y\"]}' '$TMP_DIR/plan.json' > '$TMP_DIR/plan-dyn.json' && bash generators/autofix_pr_plan.sh --plan '$TMP_DIR/plan-dyn.json' --json | jq -e '.summary.review_only == 1 and .summary.eligible == 0'"
check "pr gate reports probe recommendations" bash -c "(bash generators/pr_gate.sh --root '$TARGET' --struct '$STRUCT' --files 'src/plugins.ts' --json || true) | jq -e '(.dynamic.probe_recommendations|length) >= 1'"

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
