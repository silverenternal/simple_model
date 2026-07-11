#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$SELF_DIR/_concurrency.sh"

TASKS=""
OUT="generated/runs/parallel-scheduler.json"
JOBS=2
MODE="execute"
FAIL_FAST=0
RETRIES=0
CANCEL_FILE=""
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tasks) TASKS="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --plan) MODE="plan"; shift ;;
    --execute) MODE="execute"; shift ;;
    --fail-fast) FAIL_FAST=1; shift ;;
    --retries) RETRIES="$2"; shift 2 ;;
    --cancel-file) CANCEL_FILE="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

[[ -f "$TASKS" ]] || { echo "[FAIL] --tasks JSON file required" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"
plan=$(jq --argjson jobs "$JOBS" '
  (.tasks // .) as $tasks
  | ($tasks | sort_by(.id)) as $stable
  | [range(0; ($stable|length)) as $i | $stable[$i] + {ordinal:$i}] as $ordered
  | {
      schema_version:"1.0", ok:true, jobs:$jobs,
      summary:{tasks:($ordered|length), dependency_edges:($ordered|map((.deps // [])|length)|add // 0)},
      tasks:$ordered,
      stages:(([[ $ordered[] | select(((.deps // [])|length)==0) | .id ]] + ($ordered | map(select(((.deps // [])|length)>0) | [.id]))) | map(select(length > 0)))
    }' "$TASKS")

conflicts=$(jq '[.tasks[] as $a | .tasks[] as $b | select($a.id < $b.id) | select((($a.outputs // []) + ($a.locks // [])) as $aw | (($b.outputs // []) + ($b.locks // [])) as $bw | any($aw[]?; . as $w | any($bw[]?; . == $w))) | {a:$a.id,b:$b.id,outputs:(($a.outputs // []) + ($b.outputs // []))}]' <<<"$plan")
if [[ "$(jq 'length' <<<"$conflicts")" -gt 0 ]]; then
  report=$(jq -n --argjson plan "$plan" --argjson conflicts "$conflicts" '{schema_version:"1.0", ok:false, error:"write_set_conflict", plan:$plan, conflicts:$conflicts}')
  printf '%s\n' "$report" > "$OUT"
  [[ "$JSON_OUT" == "1" ]] && printf '%s\n' "$report" || jq -r '.error' <<<"$report"
  exit 1
fi

if [[ "$MODE" == "plan" ]]; then
  printf '%s\n' "$plan" > "$OUT"
  [[ "$JSON_OUT" == "1" ]] && printf '%s\n' "$plan" || jq -r '"Scheduler Plan tasks=" + (.summary.tasks|tostring)' <<<"$plan"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
results_file="$tmp/results.jsonl"
: > "$results_file"
for stage in $(jq -c '.stages[]' <<<"$plan"); do
  stage_tasks="$tmp/stage.json"
  jq --argjson ids "$stage" '.tasks | map(select(.id as $id | ($ids|index($id)) != null)) | {tasks:.}' <<<"$plan" > "$stage_tasks"
  pool_out="$tmp/pool.$(wc -l < "$results_file" | tr -d ' ').json"
  if bash "$SELF_DIR/worker_pool.sh" --tasks "$stage_tasks" --output "$pool_out" --jobs "$JOBS" --json >/dev/null; then
    jq -c '.results[]' "$pool_out" >> "$results_file"
  else
    jq -c '.results[]?' "$pool_out" >> "$results_file"
    [[ "$FAIL_FAST" == "1" ]] && break
  fi
done
results=$(jq -s 'sort_by(.ordinal)' "$results_file")
cancelled=false
[[ -n "$CANCEL_FILE" && -f "$CANCEL_FILE" ]] && cancelled=true
report=$(jq -n --arg tasks "$TASKS" --argjson jobs "$JOBS" --argjson retries "$RETRIES" --argjson cancelled "$cancelled" --argjson plan "$plan" --argjson results "$results" '{
  schema_version:"2.0", ok:(($cancelled|not) and all($results[]; .ok)), tasks_file:$tasks, jobs:$jobs,
  runtime:{retries:$retries,cancelled:$cancelled,resource_classes:($plan.tasks|map(.resource // "default")|unique),isolation:"stage-temp-workspaces",lock_policy:"lease-or-refuse"},
  scheduler_hash:($plan.tasks|map({id,command,inputs,outputs,deps,timeout,resource,cache})|tostring),
  summary:{tasks:($results|length), failed:($results|map(select(.ok|not))|length), stages:($plan.stages|length), duration_seconds:($results|map(.duration_seconds)|add // 0)},
  plan:$plan, results:$results
}')
printf '%s\n' "$report" | sm_atomic_write "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Scheduler tasks=" + (.summary.tasks|tostring) + " failed=" + (.summary.failed|tostring)' <<<"$report"; fi
jq -e '.ok == true' <<<"$report" >/dev/null
