#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="${BASH:-$(command -v bash)}"
MODE="fast"
CHANGED=""
JOBS=1
JSON_OUT=0
CACHE_FILE="$ROOT/generated/.cache/simple_model/test-cache.json"
OUT_DIR="$ROOT/generated/tests"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode) MODE="$2"; shift 2 ;;
    --changed-files) CHANGED="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --cache) CACHE_FILE="$2"; shift 2 ;;
    --output-dir) OUT_DIR="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

mkdir -p "$OUT_DIR"
DAG="$OUT_DIR/test-impact-dag.json"
bash "$ROOT/generators/test_impact_dag.sh" --root "$ROOT" --struct "$ROOT/struct.json" --output "$DAG" --json >/dev/null

selected=$(jq --arg mode "$MODE" --arg changed "$CHANGED" '
  def changed_match($t):
    if $changed == "" then true
    else (($changed|split(",")|map(gsub("^\\s+|\\s+$"; ""))) as $files
      | any($files[]; . as $f | ($t.inputs|any(. as $i | ($f|startswith($i)) or ($i|startswith($f)) or ($f|contains($i)) or ($i|contains($f)))))) end;
  (.selection_rules[$mode] // .selection_rules.fast) as $domains
  | [.tests[] | . as $t | select(($domains|index($t.domain)) != null) | select(changed_match(.))]
' "$DAG")
[[ "$(jq 'length' <<<"$selected")" -gt 0 ]] || selected=$(jq '.tests[0:1]' "$DAG")
REQUESTED_JOBS="$JOBS"
if [[ "$JOBS" -gt 1 ]] && jq -e 'any(.[]; ((.conflicts // [])|length) > 0 or (.domain == "core") or (.domain == "adoption"))' <<<"$selected" >/dev/null; then
  JOBS=1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
results_file="$tmp/results.jsonl"
: > "$results_file"
run_one() {
  local task="$1" id cmd start end rc result_file cache_lookup
  id=$(jq -r '.id' <<<"$task")
  cmd=$(jq -r '.command' <<<"$task")
  inputs=$(jq -r '(.inputs // []) | join(",")' <<<"$task")
  cache_lookup=$(bash "$ROOT/generators/test_cache.sh" --cache "$CACHE_FILE" --root "$ROOT" --command "$cmd" --inputs "$inputs" --lookup --json)
  if [[ "$(jq -r '.hit' <<<"$cache_lookup")" == "true" ]]; then
    jq -cn --arg id "$id" --arg cmd "$cmd" --argjson entry "$(jq '.entry' <<<"$cache_lookup")" '{id:$id, command:$cmd, cached:true, exit_code:($entry.result.exit_code // 0), duration_seconds:0, stdout_digest:($entry.result.stdout_digest // $entry.stdout_digest // ""), stderr_digest:($entry.result.stderr_digest // $entry.stderr_digest // ""), stdout_preview:($entry.result.stdout_preview // ""), stderr_preview:($entry.result.stderr_preview // ""), ok:(($entry.result.exit_code // 0)==0)}'
    return
  fi
  start=$(date +%s)
  rc=0
  stdout="$tmp/$id.out"
  stderr="$tmp/$id.err"
  (cd "$ROOT" && "$BASH_BIN" -c "$cmd") >"$stdout" 2>"$stderr" || rc=$?
  end=$(date +%s)
  stdout_hash=$( (sha256sum "$stdout" 2>/dev/null || shasum -a 256 "$stdout") | awk '{print $1}' )
  stderr_hash=$( (sha256sum "$stderr" 2>/dev/null || shasum -a 256 "$stderr") | awk '{print $1}' )
  result_file="$tmp/$id.result.json"
  jq -n --arg id "$id" --arg cmd "$cmd" --arg stdout_digest "$stdout_hash" --arg stderr_digest "$stderr_hash" --arg stdout_preview "$(tail -40 "$stdout")" --arg stderr_preview "$(tail -40 "$stderr")" --argjson rc "$rc" --argjson duration "$((end-start))" '{id:$id, command:$cmd, cached:false, exit_code:$rc, duration_seconds:$duration, stdout_digest:$stdout_digest, stderr_digest:$stderr_digest, stdout_preview:$stdout_preview, stderr_preview:$stderr_preview, ok:($rc==0)}' > "$result_file"
  bash "$ROOT/generators/test_cache.sh" --cache "$CACHE_FILE" --root "$ROOT" --command "$cmd" --inputs "$inputs" --store --result "$result_file" --json >/dev/null || true
  cat "$result_file"
}

if [[ "$JOBS" -le 1 ]]; then
  while IFS= read -r task; do
    run_one "$task" >> "$results_file"
  done < <(jq -c '.[]' <<<"$selected")
else
  idx=0
  while IFS= read -r task; do
    (run_one "$task" > "$tmp/result.$idx.json") &
    idx=$((idx+1))
    while [[ "$(jobs -rp | wc -l | tr -d ' ')" -ge "$JOBS" ]]; do sleep 0.1; done
  done < <(jq -c '.[]' <<<"$selected")
  wait
  find "$tmp" -type f -name 'result.*.json' | sort -t. -k2,2n | xargs cat >> "$results_file"
fi

results=$(jq -s '.' "$results_file")
report=$(jq -n --arg mode "$MODE" --arg changed "$CHANGED" --argjson jobs "$JOBS" --argjson requested_jobs "$REQUESTED_JOBS" --argjson selected "$selected" --argjson results "$results" '{
  schema_version:"1.0",
  ok:all($results[]; .ok),
  mode:$mode,
  changed_files:$changed,
  jobs:$jobs,
  summary:{selected:($selected|length), ran:($results|map(select(.cached|not))|length), cached:($results|map(select(.cached))|length), failed:($results|map(select(.ok|not))|length), duration_seconds:($results|map(.duration_seconds)|add // 0)},
  scheduler:{mode:(if $jobs > 1 then "parallel" else "serial" end), requested_jobs:$requested_jobs, effective_jobs:$jobs, stable_order:true, conflict_policy:"shared generated outputs force serial execution"},
  selected:$selected,
  results:$results,
  skipped_reasons:["tests outside selected mode or unaffected by changed files"]
}')
printf '%s\n' "$report" > "$OUT_DIR/test-runner.json"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Test Runner mode=" + .mode + " selected=" + (.summary.selected|tostring) + " failed=" + (.summary.failed|tostring)' <<<"$report"; fi
jq -e '.ok == true' <<<"$report" >/dev/null
