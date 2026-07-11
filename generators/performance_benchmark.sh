#!/usr/bin/env bash
set -euo pipefail

ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
OUT_DIR="generated/performance"
JOBS=2
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --output-dir) OUT_DIR="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "$SELF_DIR/.." && pwd)"
mkdir -p "$OUT_DIR"
STRUCT="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"
ROOT="$(cd "$ROOT" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

time_cmd() {
  local id="$1"; shift
  local start end rc out
  out="$tmp/$id.json"
  start=$(date +%s)
  rc=0
  "$@" >"$out" 2>"$tmp/$id.err" || rc=$?
  end=$(date +%s)
  h=$( (sha256sum "$out" 2>/dev/null || shasum -a 256 "$out") | awk '{print $1}' )
  jq -cn --arg id "$id" --arg hash "$h" --argjson rc "$rc" --argjson duration "$((end-start))" '{id:$id, ok:($rc==0), exit_code:$rc, duration_seconds:$duration, output_hash:$hash}'
}

cold_graph=$(time_cmd graph bash "$SELF_DIR/optimization_graph.sh" --root "$ROOT" --struct "$STRUCT" --output "$OUT_DIR/graph.cold.json" --json)
test_plan=$(time_cmd test_plan bash "$SELF_DIR/test_impact_dag.sh" --root "$ROOT" --struct "$STRUCT" --output "$OUT_DIR/test-impact-dag.json" --json)
serial=$(time_cmd test_fast_serial bash "$TOOL_ROOT/tools/test_runner.sh" --mode fast --jobs 1 --output-dir "$OUT_DIR/tests-serial" --json)
parallel=$(time_cmd test_fast_parallel bash "$TOOL_ROOT/tools/test_runner.sh" --mode fast --jobs "$JOBS" --output-dir "$OUT_DIR/tests-parallel" --json)
warm=$(time_cmd test_fast_warm bash "$TOOL_ROOT/tools/test_runner.sh" --mode fast --jobs "$JOBS" --output-dir "$OUT_DIR/tests-warm" --json)
jq -n '{tasks:[
  {id:"sleep_a",command:"sleep 1",cwd:".",inputs:[],outputs:[],deps:[],timeout:10,resource:"default",cache:false},
  {id:"sleep_b",command:"sleep 1",cwd:".",inputs:[],outputs:[],deps:[],timeout:10,resource:"default",cache:false}
]}' > "$tmp/scheduler-tasks.json"
sched_serial=$(time_cmd scheduler_serial bash "$SELF_DIR/parallel_scheduler.sh" --tasks "$tmp/scheduler-tasks.json" --output "$OUT_DIR/scheduler-serial.json" --jobs 1 --json)
sched_parallel=$(time_cmd scheduler_parallel bash "$SELF_DIR/parallel_scheduler.sh" --tasks "$tmp/scheduler-tasks.json" --output "$OUT_DIR/scheduler-parallel.json" --jobs "$JOBS" --json)

report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --argjson jobs "$JOBS" --argjson cold_graph "$cold_graph" --argjson test_plan "$test_plan" --argjson serial "$serial" --argjson parallel "$parallel" --argjson warm "$warm" --argjson sched_serial "$sched_serial" --argjson sched_parallel "$sched_parallel" '{
  schema_version:"1.0", ok:($cold_graph.ok and $test_plan.ok and $serial.ok and $parallel.ok and $warm.ok and $sched_serial.ok and $sched_parallel.ok),
  root:$root, struct:$struct, jobs:$jobs,
  benchmarks:[$cold_graph,$test_plan,$serial,$parallel,$warm,$sched_serial,$sched_parallel],
  summary:{
    cold_seconds:($cold_graph.duration_seconds + $test_plan.duration_seconds + $serial.duration_seconds),
    warm_seconds:$warm.duration_seconds,
    serial_test_seconds:$serial.duration_seconds,
    parallel_test_seconds:$parallel.duration_seconds,
    scheduler_serial_seconds:$sched_serial.duration_seconds,
    scheduler_parallel_seconds:$sched_parallel.duration_seconds,
    parallel_speedup:(if $sched_parallel.duration_seconds == 0 then 1 else (($sched_serial.duration_seconds / ($sched_parallel.duration_seconds|if . == 0 then 1 else . end))) end),
    deterministic_hash:([$cold_graph.output_hash,$test_plan.output_hash,$serial.output_hash,$parallel.output_hash,$warm.output_hash,$sched_serial.output_hash,$sched_parallel.output_hash]|join(":"))
  },
  budgets:{fast_check_seconds:120, full_check_seconds:900, min_cache_hit_rate:0.25, min_parallel_speedup:1}
}')
printf '%s\n' "$report" > "$OUT_DIR/scorecard.json"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Performance ok=" + (.ok|tostring) + " warm=" + (.summary.warm_seconds|tostring) + "s"' <<<"$report"; fi
jq -e '.ok == true' <<<"$report" >/dev/null
