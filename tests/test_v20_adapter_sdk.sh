#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
report="$(bash generators/adapter_conformance.sh --json)"
jq -e '.ok and .summary.reference_adapters==5 and .summary.protocol_conformance_rate==1 and (.results|length)==5 and all(.results[]; .ok)' <<<"$report" >/dev/null
printf 'function answer() { return 42; }\n' > "$tmp/source.ts"
hash="$( (sha256sum "$tmp/source.ts" 2>/dev/null || shasum -a 256 "$tmp/source.ts") | awk '{print $1}')"
jq -n --arg hash "$hash" --arg path "$tmp/source.ts" '{protocol:"adapter-protocol-v1",request_id:"test-parser",operation:"parse",language:"typescript",input:{path:$path,sha256:$hash,freshness:"current"},parameters:{}}' > "$tmp/request.json"
run_reject() {
  local adapter="$1"
  if bash tools/adapter_harness.sh --adapter "$adapter" --request "$tmp/request.json" --json > "$tmp/reject.json" 2>/dev/null; then return 1; fi
  jq -e '.ok==false and .fail_closed==true' "$tmp/reject.json" >/dev/null
}
run_reject examples/adapter-sdk/fixtures/malformed.sh
run_reject examples/adapter-sdk/fixtures/partial.sh
run_reject examples/adapter-sdk/fixtures/nondeterministic.sh
run_reject examples/adapter-sdk/fixtures/stale.sh
optional="$(bash tools/adapter_harness.sh --adapter examples/adapter-sdk/adapters/optional-reference.sh --request "$tmp/request.json" --json)"
jq -e '.ok and .response.available==false and .response.status=="unavailable" and .response.decision=="review_only" and .response.fail_closed==true' <<<"$optional" >/dev/null
first="$(bash tools/adapter_harness.sh --adapter examples/adapter-sdk/adapters/parser-reference.sh --request "$tmp/request.json" --json)"
second="$(bash tools/adapter_harness.sh --adapter examples/adapter-sdk/adapters/parser-reference.sh --request "$tmp/request.json" --json)"
cmp <(printf '%s\n' "$first") <(printf '%s\n' "$second")
echo "  [OK] adapter SDK v1"
