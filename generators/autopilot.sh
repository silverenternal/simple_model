#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
OUT_DIR="generated/autopilot"
MODE="dry-run"
CHECK_MODE="fast"
BUDGET=5
JOBS=2
CHANGED_FILES=""
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --output-dir) OUT_DIR="$2"; shift 2 ;;
    --dry-run) MODE="dry-run"; shift ;;
    --apply) MODE="apply"; shift ;;
    --mode) CHECK_MODE="$2"; shift 2 ;;
    --budget) BUDGET="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --changed-files) CHANGED_FILES="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
mkdir -p "$OUT_DIR"
ROOT="$(cd "$ROOT" && pwd)"
RUN_DIR="$OUT_DIR/run"
bash "$SELF_DIR/run_log.sh" --run-dir "$RUN_DIR" --start --json >/dev/null
structure=$(bash "$SELF_DIR/project_structure_miner.sh" --root "$ROOT" --struct "$STRUCT" --output "$OUT_DIR/project-structure.json" --json | jq '{ok,summary}')
ir=$(bash "$SELF_DIR/semantic_interface_ir.sh" --root "$ROOT" --struct "$STRUCT" --output "$OUT_DIR/interface-ir.json" --json | jq '{ok,summary}')
score=$(bash "$SELF_DIR/optimization_score.sh" --root "$ROOT" --struct "$STRUCT" --output-dir "$OUT_DIR" --json)
suggest=$(bash "$SELF_DIR/macro_suggest.sh" --root "$ROOT" --struct "$STRUCT" --output-dir "$OUT_DIR" --json)
compile=$(bash "$SELF_DIR/macro_compile.sh" --suggestions "$OUT_DIR/macro-suggestions.json" --root "$ROOT" --struct "$STRUCT" --output-dir "$OUT_DIR" --json)
graph=$(bash "$SELF_DIR/optimization_graph.sh" --root "$ROOT" --struct "$STRUCT" --output "$OUT_DIR/optimization-graph.json" --json | jq '{ok,graph_hash,summary}')
search=$(bash "$SELF_DIR/optimizer_search.sh" --graph "$OUT_DIR/optimization-graph.json" --output "$OUT_DIR/search.json" --budget "$BUDGET" --mode greedy --json)
simulate=$(bash "$SELF_DIR/macro_simulate.sh" --plan "$OUT_DIR/plan.json" --output-dir "$OUT_DIR" --jobs "$JOBS" --json || true)
policy=$(bash "$SELF_DIR/policy_eval.sh" --plan "$OUT_DIR/plan.json" --json || true)
tests=$(bash "$SELF_DIR/../tools/test_runner.sh" --mode "$CHECK_MODE" --changed-files "$CHANGED_FILES" --jobs "$JOBS" --output-dir "$OUT_DIR/tests" --json || true)
if [[ "$MODE" == "apply" ]]; then exec_result=$(bash "$SELF_DIR/macro_exec.sh" --plan "$OUT_DIR/plan.json" --apply --output-dir "$OUT_DIR" --json || true); else exec_result=$(jq -n '{ok:true, mode:"dry-run", summary:{applied:0}}'); fi
bash "$SELF_DIR/run_log.sh" --run-dir "$RUN_DIR" --append --event "$(jq -n --arg graph_hash "$(jq -r '.graph_hash' "$OUT_DIR/optimization-graph.json")" --arg stop "$(jq -r '.stop_reason' "$OUT_DIR/search.json")" '{event:"autopilot_decision", graph_hash:$graph_hash, stop_reason:$stop}')" --json >/dev/null
report=$(jq -n --arg mode "$MODE" --arg check_mode "$CHECK_MODE" --arg changed "$CHANGED_FILES" --arg root "$ROOT" --arg struct "$STRUCT" --argjson jobs "$JOBS" --argjson budget "$BUDGET" --argjson structure "$structure" --argjson ir "$ir" --argjson score "$score" --argjson suggest "$suggest" --argjson compile "$compile" --argjson graph "$graph" --argjson search "$search" --argjson simulate "$simulate" --argjson policy "$policy" --argjson tests "$tests" --argjson execution "$exec_result" '{
  schema_version:"2.0", ok:($compile.ok and ($simulate.ok // true) and (($policy.ok // true) == true) and ($execution.ok == true) and ($tests.ok // true)), mode:$mode, check_mode:$check_mode, changed_files:$changed, root:$root, struct:$struct,
  controls:{jobs:$jobs,budget:$budget},
  stop_reason:$search.stop_reason,
  graph_hash:$graph.graph_hash,
  phases:{structure:$structure.summary, semantic_ir:$ir.summary, score:{score:$score.score,debt:$score.debt}, suggestions:$suggest.summary, compile:$compile.summary, graph:$graph.summary, search:$search.summary, simulation:$simulate.summary, policy:$policy.summary, tests:$tests.summary, execution:$execution.summary},
  selected_candidates:$search.selected,
  rejected_candidates:$search.rejected,
  cache_usage:{tests:{cached:($tests.summary.cached // 0), ran:($tests.summary.ran // 0)}},
  parallel_tasks:{jobs:$jobs, macro_partitions:($simulate.concurrency.partitions // []), test_scheduler:($tests.scheduler // {})},
  timings:{tests_seconds:($tests.summary.duration_seconds // 0), simulation_changed_files:($simulate.summary.changed_files // 0)},
  artifacts:{project_structure:"project-structure.json", interface_ir:"interface-ir.json", optimization_graph:"optimization-graph.json", search:"search.json", plan:"plan.json", simulation:"simulation.json", tests:"tests/test-runner.json"},
  next_commands:["simple_model_pi.sh context-pack --workflow optimize --json","simple_model_pi.sh macro-run --plan generated/autopilot/plan.json --dry-run --json","simple_model_pi.sh fast-check --json"]
}')
printf '%s\n' "$report" > "$OUT_DIR/autopilot.json"
bash "$SELF_DIR/run_log.sh" --run-dir "$RUN_DIR" --finalize --report "$OUT_DIR/autopilot.json" --json >/dev/null
{ echo "# Autopilot Report"; echo; jq -r '"- ok: " + (.ok|tostring), "- score: " + (.phases.score.score|tostring), "- graph hash: " + (.graph_hash|tostring), "- selected candidates: " + ((.phases.search.selected // 0)|tostring), "- stop reason: " + .stop_reason, "- simulated actions: " + ((.phases.simulation.actions // 0)|tostring), "- test cache hits: " + ((.cache_usage.tests.cached // 0)|tostring)' <<<"$report"; } > "$OUT_DIR/autopilot.md"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else cat "$OUT_DIR/autopilot.md"; fi
