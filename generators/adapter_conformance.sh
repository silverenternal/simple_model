#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADAPTER_DIR="$ROOT/examples/adapter-sdk/adapters"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --json) JSON_OUT=1; shift ;;
    --adapter-dir) ADAPTER_DIR="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf 'function answer() { return 42; }\n' > "$tmp/source.ts"
hash="$( (sha256sum "$tmp/source.ts" 2>/dev/null || shasum -a 256 "$tmp/source.ts") | awk '{print $1}')"
make_request() { jq -n --arg id "$1" --arg op "$2" --arg lang "$3" --arg path "$tmp/source.ts" --arg hash "$hash" '{protocol:"adapter-protocol-v1",request_id:$id,operation:$op,language:$lang,input:{path:$path,sha256:$hash,freshness:"current"},parameters:{}}'; }
ids=(parser-reference query-reference rewrite-reference runtime-reference optional-reference)
ops=(parse query rewrite runtime_evidence parse)
langs=(typescript typescript typescript typescript typescript)
results="$tmp/results.jsonl"; : > "$results"
for i in "${!ids[@]}"; do
  request="$tmp/request-$i.json"; make_request "conformance-$i" "${ops[$i]}" "${langs[$i]}" > "$request"
  adapter="$ADAPTER_DIR/${ids[$i]}.sh"; [[ -x "$adapter" ]] || { echo "missing adapter: $adapter" >&2; exit 2; }
  result="$tmp/report-$i.json"; rc=0
  bash "$ROOT/tools/adapter_harness.sh" --adapter "$adapter" --request "$request" --json > "$result" || rc=$?
  jq -c --arg id "${ids[$i]}" --argjson rc "$rc" '. + {fixture_id:$id,exit_code:$rc}' "$result" >> "$results"
done
all_results="$(jq -s '.' "$results")"
passed="$(jq '[.[]|select(.ok==true)]|length' <<<"$all_results")"; total="$(jq 'length' <<<"$all_results")"
rate="$(jq -n --argjson p "$passed" --argjson t "$total" 'if $t==0 then 0 else ($p/$t) end')"
report="$(jq -n --argjson results "$all_results" --argjson passed "$passed" --argjson total "$total" --argjson rate "$rate" '{schema_version:"1.0",ok:($passed==$total and $rate==1),summary:{reference_adapters:$total,passed:$passed,failed:($total-$passed),protocol_conformance_rate:$rate},results:$results,fail_closed_baseline:{unavailable_optional_is_review_only:true,network:false,structural_decisions:0}}')"
if [[ "$JSON_OUT" == 1 ]]; then printf '%s\n' "$report"; else jq -r '"Adapter conformance reference_adapters=\(.summary.reference_adapters) rate=\(.summary.protocol_conformance_rate)"' <<<"$report"; fi
jq -e '.ok==true' <<<"$report" >/dev/null
