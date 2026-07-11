#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{macro_id:"safe-a",reads:{files:["src/shared.ts"],symbols:["sym:config"]},writes:{files:["src/a.ts"],tests:["tests/a"],contracts:["api:a"]},aliases:[{from:"sym:config",to:"sym:config"}]}' > "$tmp/a.json"
jq -n '{macro_id:"safe-b",reads:{files:["src/shared.ts"],symbols:["sym:other"]},writes:{files:["src/b.ts"],tests:["tests/b"],contracts:["api:b"]}}' > "$tmp/b.json"
jq -n '{macro_id:"conflict",reads:{files:["src/a.ts"]},writes:{files:["src/shared.ts"]}}' > "$tmp/conflict.json"
jq -n '{macro_id:"unknown",reads:{files:["src/x.ts"]},writes:{files:["src/y.ts"]},unknown_aliases:["sym:dynamic"]}' > "$tmp/unknown.json"
jq -n '{macro_id:"cycle",aliases:[{from:"x",to:"y"},{from:"y",to:"x"}]}' > "$tmp/cycle.json"
for id in a b conflict unknown; do bash generators/effect_infer.sh --input "$tmp/$id.json" --output "$tmp/$id-effects.json" --json >/dev/null; done
jq -e '.summary.effects==5 and any(.effects[];.kind=="contract") and any(.effects[];.kind=="test")' "$tmp/a-effects.json" >/dev/null
bash generators/commutativity_check.sh --left "$tmp/a-effects.json" --right "$tmp/b-effects.json" --output "$tmp/safe.json" --json >/dev/null
jq -e '.commute and .counterexamples==[] and .equivalence.proven' "$tmp/safe.json" >/dev/null
bash generators/commutativity_check.sh --left "$tmp/a-effects.json" --right "$tmp/conflict-effects.json" --output "$tmp/conflict.json" --json >/dev/null
jq -e '.commute==false and any(.counterexamples[];.kind=="write_read")' "$tmp/conflict.json" >/dev/null
bash generators/commutativity_check.sh --left "$tmp/a-effects.json" --right "$tmp/unknown-effects.json" --output "$tmp/unknown-report.json" --json >/dev/null
jq -e '.commute==false and any(.counterexamples[];.kind=="unknown_alias")' "$tmp/unknown-report.json" >/dev/null
if bash generators/alias_resolve.sh --input "$tmp/cycle.json" --output "$tmp/cycle-report.json" --json >/dev/null; then exit 1; fi
jq -e '.ok==false and .summary.cycles>0' "$tmp/cycle-report.json" >/dev/null
jq -n --slurpfile a "$tmp/a-effects.json" --slurpfile b "$tmp/b-effects.json" --slurpfile c "$tmp/conflict-effects.json" '[$a[0],$b[0],$c[0]]' > "$tmp/batch.json"
bash generators/commutativity_check.sh --batch "$tmp/batch.json" --output "$tmp/batch-report.json" --json >/dev/null
jq -e '.summary.false_commutativity_accepts==0 and .summary.parallelizable_safe_plan_ratio>=0.30 and .equivalence.proven' "$tmp/batch-report.json" >/dev/null
echo "  [OK] effect solver false_commutativity=0 parallel_ratio>=0.30"
