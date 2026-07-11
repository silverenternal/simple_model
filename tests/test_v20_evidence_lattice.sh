#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '[{id:"a",subject:"interface:x",class:"parsed",verdict:"safe",provenance:["static"],freshness:"current",invalidation_keys:["src/x"]}]' > "$tmp/a.json"
jq -n '[{id:"b",subject:"interface:x",class:"runtime",verdict:"unsafe",provenance:["trace:1"],freshness:"current",invalidation_keys:["trace"]},{id:"c",subject:"interface:y",class:"parsed",verdict:"safe",provenance:["static"],freshness:"stale",invalidation_keys:["src/y"]}]' > "$tmp/b.json"
bash generators/evidence_join.sh -i "$tmp/a.json" -i "$tmp/b.json" -o "$tmp/ab.json" --json >/dev/null
bash generators/evidence_join.sh -i "$tmp/b.json" -i "$tmp/a.json" -o "$tmp/ba.json" --json >/dev/null
cmp "$tmp/ab.json" "$tmp/ba.json" || exit 1
jq -e '.summary.conflicts==1 and (.subjects[]|select(.subject=="interface:x")|.state)=="conflict" and (.subjects[]|select(.subject=="interface:y")|.state)=="stale"' "$tmp/ab.json"
bash generators/evidence_explain.sh --ledger "$tmp/ab.json" --subject interface:x --json | jq -e '.minimal_evidence_needed.count==1 and .blockers==["contradictory_current_evidence"]'
echo "  [OK] evidence lattice"
