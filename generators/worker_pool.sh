#!/usr/bin/env bash
set -euo pipefail

TASKS=""
OUT="generated/runs/worker-pool.json"
JOBS=2
FAIL_FAST=0
JSON_OUT=0
BASH_BIN="${BASH:-$(command -v bash)}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --tasks) TASKS="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --fail-fast) FAIL_FAST=1; shift ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

[[ -f "$TASKS" ]] || { echo "[FAIL] --tasks JSON file required" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
events="$tmp/events.jsonl"
: > "$events"

run_task() {
  local task="$1" idx="$2" id cmd cwd timeout start end rc stdout stderr stdout_hash stderr_hash
  id=$(jq -r '.id' <<<"$task")
  cmd=$(jq -r '.command' <<<"$task")
  cwd=$(jq -r '.cwd // "."' <<<"$task")
  timeout=$(jq -r '.timeout // 300' <<<"$task")
  stdout="$tmp/$idx.stdout"
  stderr="$tmp/$idx.stderr"
  start=$(date +%s)
  jq -cn --arg id "$id" --arg event "start" --argjson ordinal "$idx" '{event:$event,id:$id,ordinal:$ordinal}' >> "$events"
  rc=0
  if command -v timeout >/dev/null 2>&1; then
    (cd "$cwd" && timeout "$timeout" "$BASH_BIN" -c "$cmd") >"$stdout" 2>"$stderr" || rc=$?
  else
    (cd "$cwd" && "$BASH_BIN" -c "$cmd") >"$stdout" 2>"$stderr" || rc=$?
  fi
  end=$(date +%s)
  stdout_hash=$( (sha256sum "$stdout" 2>/dev/null || shasum -a 256 "$stdout") | awk '{print $1}' )
  stderr_hash=$( (sha256sum "$stderr" 2>/dev/null || shasum -a 256 "$stderr") | awk '{print $1}' )
  jq -cn --arg id "$id" --arg event "end" --argjson ordinal "$idx" --argjson exit_code "$rc" '{event:$event,id:$id,ordinal:$ordinal,exit_code:$exit_code}' >> "$events"
  jq -n --arg id "$id" --arg command "$cmd" --arg cwd "$cwd" --arg stdout_digest "$stdout_hash" --arg stderr_digest "$stderr_hash" --argjson ordinal "$idx" --argjson exit_code "$rc" --argjson duration "$((end-start))" '{
    id:$id, ordinal:$ordinal, command:$command, cwd:$cwd, exit_code:$exit_code, ok:($exit_code == 0),
    duration_seconds:$duration, stdout_digest:$stdout_digest, stderr_digest:$stderr_digest,
    stdout_preview:($ARGS.positional[0] // ""), stderr_preview:($ARGS.positional[1] // "")
  }' --args "$(head -c 4000 "$stdout")" "$(head -c 4000 "$stderr")" > "$tmp/result.$idx.json"
}

idx=0
while IFS= read -r task; do
  if [[ "$JOBS" -le 1 ]]; then
    run_task "$task" "$idx"
    if [[ "$FAIL_FAST" == "1" ]] && ! jq -e '.ok' "$tmp/result.$idx.json" >/dev/null; then break; fi
  else
    (run_task "$task" "$idx") &
    while [[ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$JOBS" ]]; do sleep 0.05; done
  fi
  idx=$((idx+1))
done < <(jq -c '(.tasks // .)[]' "$TASKS")
wait || true

results=$(find "$tmp" -type f -name 'result.*.json' | sort -t. -k2,2n | xargs cat 2>/dev/null | jq -s 'sort_by(.ordinal)')
event_log=$(jq -s '.' "$events")
report=$(jq -n --arg tasks "$TASKS" --argjson jobs "$JOBS" --argjson results "$results" --argjson event_log "$event_log" '{
  schema_version:"1.0", ok:all($results[]; .ok), tasks_file:$tasks, jobs:$jobs,
  summary:{tasks:($results|length), failed:($results|map(select(.ok|not))|length), duration_seconds:($results|map(.duration_seconds)|add // 0)},
  results:$results,
  event_log:$event_log
}')
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Worker Pool tasks=" + (.summary.tasks|tostring) + " failed=" + (.summary.failed|tostring)' <<<"$report"; fi
jq -e '.ok == true' <<<"$report" >/dev/null
