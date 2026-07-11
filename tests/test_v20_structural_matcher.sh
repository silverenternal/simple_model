#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
! rg -q '(^|[^a-zA-Z])test\(' generators/structural_match.sh
bash generators/structural_match.sh --query benchmarks/structural-matcher/query.json --graph benchmarks/structural-matcher/baseline.json --output "$tmp/baseline.json" --json >/dev/null
bash generators/structural_match.sh --query benchmarks/structural-matcher/query.json --graph benchmarks/structural-matcher/formatted.json --output "$tmp/formatted.json" --json >/dev/null
bash generators/capture_stability.sh --baseline "$tmp/baseline.json" --candidate "$tmp/formatted.json" --output "$tmp/stability.json" --json >/dev/null
bash generators/structural_match.sh --query benchmarks/structural-matcher/query.json --graph benchmarks/structural-matcher/ambiguous.json --output "$tmp/ambiguous.json" --json >/dev/null
expected="$(jq '.expected_node_ids' benchmarks/structural-matcher/labels.json)"
predicted="$(jq '[.matches[].node_id]' "$tmp/baseline.json")"
metrics="$(jq -n --argjson expected "$expected" --argjson predicted "$predicted" '{tp:(($predicted-($predicted-$expected))|length),fp:(($predicted-$expected)|length),fn:(($expected-$predicted)|length)} | .precision=(if (.tp+.fp)==0 then 0 else (.tp/(.tp+.fp)) end) | .recall=(if (.tp+.fn)==0 then 0 else (.tp/(.tp+.fn)) end)')"
jq -e --argjson m "$metrics" '.precision>=0.99 and .recall>=0.97 and .fp==0 and .fn==0' <<<"$metrics" >/dev/null
jq -e '.summary.matches==3 and .summary.ambiguous==false and .summary.apply_allowed==true' "$tmp/baseline.json" >/dev/null
jq -e '.stable==true and .apply_allowed==true and .changed==[]' "$tmp/stability.json" >/dev/null
jq -e '.summary.ambiguous==true and .summary.apply_allowed==false and any(.diagnostics[];.code=="duplicate_stable_identity")' "$tmp/ambiguous.json" >/dev/null
jq -e --argjson m "$metrics" '{schema_version:"1.0",ok:($m.precision>=0.99 and $m.recall>=0.97),metrics:$m}' <<<"{}" >/dev/null
echo "  [OK] structural matcher precision=$(jq -r '.precision' <<<"$metrics") recall=$(jq -r '.recall' <<<"$metrics")"
