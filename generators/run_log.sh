#!/usr/bin/env bash
set -euo pipefail

MODE="append"
RUN_DIR="generated/runs/latest"
EVENT=""
REPORT=""
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run-dir) RUN_DIR="$2"; shift 2 ;;
    --event) EVENT="$2"; shift 2 ;;
    --report) REPORT="$2"; shift 2 ;;
    --start) MODE="start"; shift ;;
    --append) MODE="append"; shift ;;
    --finalize) MODE="finalize"; shift ;;
    --replay) MODE="replay"; shift ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

mkdir -p "$RUN_DIR"
events="$RUN_DIR/events.jsonl"
summary="$RUN_DIR/summary.json"

hash_file() {
  local f="$1"
  [[ -f "$f" ]] || { echo ""; return; }
  (sha256sum "$f" 2>/dev/null || shasum -a 256 "$f") | awk '{print $1}'
}

case "$MODE" in
  start)
    : > "$events"
    report=$(jq -n --arg run_dir "$RUN_DIR" '{schema_version:"1.0", ok:true, mode:"start", run_dir:$run_dir}')
    ;;
  append)
    [[ -n "$EVENT" ]] || EVENT='{}'
    jq -c --arg ordinal "$(wc -l < "$events" 2>/dev/null | tr -d ' ' || echo 0)" '. + {ordinal:($ordinal|tonumber)}' <<<"$EVENT" >> "$events"
    report=$(jq -n --arg run_dir "$RUN_DIR" '{schema_version:"1.0", ok:true, mode:"append", run_dir:$run_dir}')
    ;;
  finalize)
    [[ -f "$events" ]] || : > "$events"
    event_hash=$(hash_file "$events")
    report_hash=$(hash_file "$REPORT")
    event_count=$(jq -s 'length' "$events")
    report=$(jq -n --arg run_dir "$RUN_DIR" --arg event_hash "$event_hash" --arg report "$REPORT" --arg report_hash "$report_hash" --argjson event_count "$event_count" '{
      schema_version:"1.0", ok:true, mode:"finalize", run_dir:$run_dir,
      event_hash:$event_hash, report:$report, report_hash:$report_hash,
      summary:{events:$event_count}
    }')
    printf '%s\n' "$report" > "$summary"
    ;;
  replay)
    [[ -f "$summary" && -f "$events" ]] || { echo "[FAIL] replay needs summary and events" >&2; exit 2; }
    expected=$(jq -r '.event_hash' "$summary")
    actual=$(hash_file "$events")
    report=$(jq -n --arg run_dir "$RUN_DIR" --arg expected "$expected" --arg actual "$actual" '{schema_version:"1.0", ok:($expected==$actual), mode:"replay", run_dir:$run_dir, expected_event_hash:$expected, actual_event_hash:$actual, checks:{event_log_matches:($expected==$actual)}}')
    ;;
esac

if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Run Log " + .mode + " ok=" + (.ok|tostring)' <<<"$report"; fi
jq -e '.ok == true' <<<"$report" >/dev/null
