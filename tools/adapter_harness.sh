#!/usr/bin/env bash
set -euo pipefail

ADAPTER=""; REQUEST=""; OUT=""; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --adapter|-a) ADAPTER="$2"; shift 2 ;;
    --request|-r) REQUEST="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    -h|--help) echo "adapter_harness.sh --adapter <executable> --request <json> [--output <json>] [--json]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -n "$ADAPTER" && -x "$ADAPTER" ]] || { echo "--adapter must be executable" >&2; exit 64; }
[[ -f "$REQUEST" ]] || { echo "--request JSON is required" >&2; exit 64; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
manifest="$tmp/manifest.json"; response1="$tmp/response-1.json"; response2="$tmp/response-2.json"

run_adapter() {
  local mode="$1" output="$2" timeout_ms="$3" request_path="${4:-}" seconds
  seconds="$(( (timeout_ms + 999) / 1000 ))"
  if command -v timeout >/dev/null 2>&1; then
    timeout "$seconds" "$ADAPTER" "$mode" "$request_path" >"$output" 2>"$output.stderr"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$seconds" "$ADAPTER" "$mode" "$request_path" >"$output" 2>"$output.stderr"
  else
    "$ADAPTER" "$mode" "$request_path" >"$output" 2>"$output.stderr"
  fi
}
fail() {
  local reason="$1" report
  report="$(jq -n --arg reason "$reason" --arg adapter "$ADAPTER" --arg request "$REQUEST" '{schema_version:"1.0",ok:false,adapter:$adapter,request:$request,error:{code:"adapter_rejected",reason:$reason},fail_closed:true}')"
  [[ -z "$OUT" ]] || printf '%s\n' "$report" > "$OUT"
  printf '%s\n' "$report"
  exit 3
}

manifest_rc=0; run_adapter --manifest "$manifest" 5000 || manifest_rc=$?
[[ "$manifest_rc" -eq 0 ]] || fail "manifest command failed or timed out"
jq -e 'type=="object" and .protocol=="adapter-protocol-v1" and (.adapter.id|type)=="string" and (.adapter.version|test("^[0-9]+\\.[0-9]+\\.[0-9]+$")) and (.capabilities|type)=="array" and (.capabilities|length)>0 and (.languages|type)=="array" and (.languages|length)>0 and (.provenance.source|type)=="string" and (.provenance.tool|type)=="string" and (.provenance.version|type)=="string" and (.provenance.mode|IN("fixture","local","sandbox","remote")) and (.limits.timeout_ms|type)=="number" and .limits.timeout_ms>=1 and (.limits.max_output_bytes|type)=="number" and .limits.max_output_bytes>=1024 and (.sandbox.required|type)=="boolean" and .sandbox.network==false and (.sandbox.write_paths|type)=="array" and .deterministic==true' "$manifest" >/dev/null || fail "invalid or incomplete manifest"
request_protocol="$(jq -r '.protocol // empty' "$REQUEST")"; [[ "$request_protocol" == "adapter-protocol-v1" ]] || fail "request protocol mismatch"
operation="$(jq -r '.operation // empty' "$REQUEST")"; language="$(jq -r '.language // empty' "$REQUEST")"; request_id="$(jq -r '.request_id // empty' "$REQUEST")"
[[ "$operation" =~ ^(parse|query|rewrite|runtime_evidence)$ && -n "$language" && -n "$request_id" ]] || fail "malformed request"
capability="$(case "$operation" in parse) printf parser ;; query) printf query ;; rewrite) printf rewrite ;; runtime_evidence) printf runtime_evidence ;; esac)"
jq -e --arg capability "$capability" --arg lang "$language" '(.capabilities|index($capability)) != null and (.languages|index($lang)) != null' "$manifest" >/dev/null || fail "capability or language negotiation failed"
[[ "$(jq -r '.input.freshness // empty' "$REQUEST")" == "current" ]] || fail "stale input"
input_hash="$(jq -r '.input.sha256 // empty' "$REQUEST")"; [[ "$input_hash" =~ ^[a-f0-9]{64}$ ]] || fail "missing input hash"
max_bytes="$(jq -r '.limits.max_output_bytes' "$manifest")"; timeout_ms="$(jq -r '.limits.timeout_ms' "$manifest")"
rc=0; run_adapter --request "$response1" "$timeout_ms" "$REQUEST" || rc=$?; [[ "$rc" -eq 0 ]] || fail "request command failed or timed out"
[[ "$(wc -c < "$response1" | tr -d ' ')" -le "$max_bytes" ]] || fail "response exceeds manifest output limit"
rc=0; run_adapter --request "$response2" "$timeout_ms" "$REQUEST" || rc=$?; [[ "$rc" -eq 0 ]] || fail "second request command failed or timed out"
cmp "$response1" "$response2" >/dev/null || fail "nondeterministic response"
jq -e --arg id "$request_id" --arg op "$operation" --arg lang "$language" --arg hash "$input_hash" 'type=="object" and .protocol=="adapter-protocol-v1" and .request_id==$id and .operation==$op and .language==$lang and (.adapter.id|type)=="string" and (.adapter.version|type)=="string" and (.available|type)=="boolean" and (.status|IN("ok","unavailable")) and (.result|type)=="object" and (.provenance.source|type)=="string" and (.provenance.tool|type)=="string" and (.provenance.version|type)=="string" and (.provenance.mode|IN("fixture","local","sandbox","remote")) and .input.sha256==$hash and .input.freshness=="current" and (.write_set|type)=="array" and .deterministic==true and (.decision|IN("accept","review_only","reject")) and .fail_closed==true' "$response1" >/dev/null || fail "malformed or partial response"
manifest_json="$(cat "$manifest")"
jq -e '((.available==false and .status=="unavailable" and .decision!="accept") or (.available==true and .status=="ok" and .decision=="accept"))' "$response1" >/dev/null || fail "availability or decision invariant failed"
if [[ "$operation" == "rewrite" ]]; then
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    jq -e --arg path "$path" 'any(.sandbox.write_paths[]; . as $allowed | ($path == $allowed) or ($path|startswith(($allowed|rtrimstr("/"))+"/")))' "$manifest" >/dev/null || fail "rewrite write_set escapes sandbox"
  done < <(jq -r '.write_set[]' "$response1")
fi
report="$(jq -n --slurpfile manifest "$manifest" --slurpfile response "$response1" '{schema_version:"1.0",ok:true,adapter:$manifest[0].adapter,capabilities:$manifest[0].capabilities,languages:$manifest[0].languages,manifest:$manifest[0],response:$response[0],fail_closed:true}')"
[[ -z "$OUT" ]] || printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then printf '%s\n' "$report"; else jq -r '"Adapter \(.adapter.id) operation=\(.response.operation) status=\(.response.status)"' <<<"$report"; fi
