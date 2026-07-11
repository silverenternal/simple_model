#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
pass=0; fail=0; EXIT_CODE=0
check(){
  local n="$1" start elapsed; shift
  start=$SECONDS
  if "$@" >/dev/null 2>&1; then
    elapsed=$((SECONDS - start)); printf '  [OK]   %-36s %4ss\n' "$n" "$elapsed"; pass=$((pass+1))
  else
    elapsed=$((SECONDS - start)); printf '  [FAIL] %-36s %4ss\n' "$n" "$elapsed"; fail=$((fail+1)); EXIT_CODE=1
  fi
}

cd "$ROOT_DIR"
TARGET="$ROOT_DIR/examples/plugin-target-repo"
OPT="$ROOT_DIR/examples/optimization-target-repo"
WRAP="$ROOT_DIR/codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh"

check "semantic interface schema" jq -e '.properties.nodes.items.required|index("parser")' specs/semantic-interface-ir.json
check "macro ir v2 schema" jq -e '.properties.safety.required|index("idempotency_key")' macros/macro-ir-v2.schema.json
check "policy schema" jq -e '.properties.macro.properties.max_risk' specs/policy.schema.json
check "parser backend matrix" bash -c "bash generators/parser_backends.sh --root '$TARGET' --json | jq -e '.summary.languages >= 10 and .summary.repo_files >= 1 and (.backends[]|select(.language==\"python\" and has(\"evidence\")))'"
check "deep parser probe" bash -c "bash generators/deep_parser_probe.sh --root '$TARGET' --json | jq -e '.ok == true and .summary.files >= 1 and .backend_summary.repo_files >= 1'"
check "project structure miner" bash -c "bash generators/project_structure_miner.sh --root '$TARGET' --struct '$TARGET/struct.json' --output '$TMP_DIR/project-structure.json' --json | jq -e '.summary.files >= 1 and (.suggestions|type==\"array\")'"
check "framework surfaces" bash -c "bash generators/framework_surfaces.sh --root '$TARGET' --struct '$TARGET/struct.json' --json | jq -e '.ok == true and (.surfaces|type==\"array\")'"
check "contract graph" bash -c "bash generators/contract_graph.sh --root '$TARGET' --struct '$TARGET/struct.json' --json | jq -e '.ok == true and (.contracts|type==\"array\")'"
check "semantic interface ir" bash -c "bash generators/semantic_interface_ir.sh --root '$TARGET' --struct '$TARGET/struct.json' --output '$TMP_DIR/interface-ir.json' --json | jq -e '.schema_version == \"2.0\" and .summary.nodes >= 1 and all(.nodes[]; .parser and .confidence)'"
check "index cache cold" bash -c "bash generators/index_cache.sh --root '$TARGET' --struct '$TARGET/struct.json' --cache '$TMP_DIR/index-cache.json' --json | jq -e '.summary.misses >= 1'"
check "index cache warm" bash -c "bash generators/index_cache.sh --root '$TARGET' --struct '$TARGET/struct.json' --cache '$TMP_DIR/index-cache.json' --json | jq -e '.summary.hits >= 1'"
check "workspace graph" bash -c "bash generators/workspace_graph.sh --root '$TARGET' --struct '$TARGET/struct.json' --output '$TMP_DIR/workspace-graph.json' --json | jq -e '.summary.components >= 1'"
check "macro pack registry" bash -c "bash generators/macro_registry.sh --json | jq -e '.schema_version == \"2.0\" and (.packs[]|select(.name==\"semantic-refactor\"))'"
check "macro family suggest" bash -c "bash generators/macro_family_suggest.sh --root '$TARGET' --struct '$TARGET/struct.json' --output-dir '$TMP_DIR/families' --json | jq -e '.summary.families >= 2'"
check "macro suggest v2 inputs" bash -c "bash generators/macro_suggest.sh --root '$OPT' --struct '$OPT/struct.json' --output-dir '$TMP_DIR/opt' --json | jq -e '.summary.suggestions >= 1'"
check "macro rank" bash -c "bash generators/macro_rank.sh --suggestions '$TMP_DIR/opt/macro-suggestions.json' --json | jq -e '.summary.candidates >= 1 and .ranked[0].rank_score'"
check "macro compile" bash -c "bash generators/macro_compile.sh --suggestions '$TMP_DIR/opt/macro-suggestions.json' --root '$OPT' --struct '$OPT/struct.json' --output-dir '$TMP_DIR/opt' --json | jq -e '.summary.actions >= 1 and all(.actions[]; .execution_tier and .policy.policy_required == true)'"
check "macro simulation" bash -c "bash generators/macro_simulate.sh --plan '$TMP_DIR/opt/plan.json' --output-dir '$TMP_DIR/opt' --json | jq -e '.mode == \"simulation\" and .rollback_feasible == true'"
check "policy engine" bash -c "bash generators/policy_eval.sh --plan '$TMP_DIR/opt/plan.json' --json | jq -e '.schema_version == \"2.0\" and (.decision == \"allow\" or .decision == \"deny\")'"
cat > "$TMP_DIR/safe-codemod-plan.json" <<JSON
{"schema_version":"1.0","root":"$OPT","struct":"$OPT/struct.json","actions":[{"id":"demo.safe","macro_id":"package_boundary_repair","risk":"medium","execution_tier":"safe_codemod","policy":{"simulation_required":true}}]}
JSON
check "safe codemod requires simulation" bash -c "! bash generators/policy_eval.sh --plan '$TMP_DIR/safe-codemod-plan.json' --json"
check "autofix pr plan" bash -c "bash generators/autofix_pr_plan.sh --plan '$TMP_DIR/opt/plan.json' --json | jq -e '.mode == \"dry-run\" and (.eligible|type==\"array\")'"
check "test graph" bash -c "bash generators/test_graph.sh --root '$TARGET' --struct '$TARGET/struct.json' --json | jq -e '.summary.tests >= 0 and (.gaps|type==\"array\")'"
check "context pack" bash -c "bash generators/codex_context_pack.sh --root '$TARGET' --struct '$TARGET/struct.json' --workflow optimize --output-dir '$TMP_DIR/context' --json | jq -e '.workflow == \"optimize\" and .graph_slice.summary.nodes >= 1'"
check "autopilot" bash -c "bash generators/autopilot.sh --root '$TARGET' --struct '$TARGET/struct.json' --output-dir '$TMP_DIR/autopilot' --dry-run --json | jq -e '.ok == true and .phases.semantic_ir.nodes >= 1'"
check "onboard" bash -c "bash generators/onboard.sh --root '$TARGET' --struct '$TARGET/struct.json' --output-dir '$TMP_DIR/onboard' --json | jq -e '.ok == true and .phases.context_pack == \"adopt\"'"
check "terminal report renderer" bash -c "bash generators/report_render.sh --input '$TMP_DIR/autopilot/autopilot.json' --title autopilot | grep -q 'autopilot'"
check "benchmark scorecard" bash -c "bash generators/benchmark_scorecard.sh '$TARGET' --json | jq -e '.schema_version == \"2.0\" and .ok == true and .summary.cases >= 20 and .metrics.macro_simulation_safety == 1'"
check "competitive scorecard" bash -c "bash generators/competitive_scorecard.sh --benchmark generated/benchmarks/scorecard.json --json | jq -e '.ok == true and (.tools[]|select(.name==\"simple_model\" and .benchmarked==true))'"
check "adoption report" bash -c "bash generators/adoption_report.sh --root '$TARGET' --struct '$TARGET/struct.json' --output-dir '$TMP_DIR/adoption-report' --benchmark generated/benchmarks/scorecard.json --json | jq -e '.ok == true and .benchmark.cases >= 20 and (.competitive.tools >= 5)'"
check "release slo" bash -c "bash generators/release_slo.sh --json | jq -e '.ok == true'"
check "self optimization harness" bash -c "bash examples/self-optimization/run.sh | jq -e '.ok == true and .plan.actions >= 0 and .simulation.actions >= 0'"
check "plugin command manifest v07" bash -c "jq -e '.schema_version == \"1.2\" and (.commands[]|select(.name==\"autopilot\")) and all(.commands[]; ((.tests // [])|length)>0 and has(\"release_gate\"))' codex/skills/simple-model-project-intelligence/references/command-manifest.json"
check "plugin semantic-ir command" bash -c "'$WRAP' --target-root '$TARGET' --struct '$TARGET/struct.json' semantic-ir --json | jq -e '.schema_version == \"2.0\"'"
check "plugin autopilot command" bash -c "'$WRAP' --target-root '$TARGET' --struct '$TARGET/struct.json' autopilot --dry-run --output-dir '$TMP_DIR/wrap-autopilot' --json | jq -e '.ok == true'"
check "plugin adoption report command" bash -c "'$WRAP' --target-root '$TARGET' --struct '$TARGET/struct.json' adoption-report --output-dir '$TMP_DIR/wrap-report' --benchmark generated/benchmarks/scorecard.json --json | jq -e '.ok == true and .benchmark.cases >= 20'"
check "mcp exposes v07 tool" bash -c "printf '{\"id\":1,\"method\":\"tools/list\"}\\n' | SIMPLE_MODEL_ROOT='$ROOT_DIR' bash tools/simple_model_mcp.sh | jq -e '.result.tools[]|select(.name==\"plugin_semantic_ir\")'"
check "docs for production surfaces" bash -c "test -f docs/PARSER_BACKENDS.md && test -f docs/MACRO_PACKS.md && test -f docs/BENCHMARKS.md && test -f docs/RELEASE_SLO.md && test -f docs/playbooks/new-repo-adoption.md"
check "todo roadmap v2 executable macro wisdom planned" bash -c "jq -e '.version == \"2.0-executable-macro-wisdom-roadmap\" and .status == \"planned\" and (.waves|length) >= 7 and (.todos|length) >= 45 and all(.todos[]; ((.status == \"pending\" or .status == \"done\")) and (.acceptance|length)>=4 and (.deliverables|length)>=4 and (.dependencies|type)==\"array\" and (.metrics|type)==\"object\") and (([.todos[].id]|length)==([.todos[].id]|unique|length))' todo.json"

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
