#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{schema_version:"1.0",examples:[{id:"one",before:{name:"old",kind:"route"},after:{name:"new",kind:"route"}}]}' > "$tmp/one.json"
bash generators/example_to_macro.sh --input "$tmp/one.json" --output "$tmp/one-report.json" --json >/dev/null
jq -e '.summary.single_example_apply_promotions==0 and all(.candidates[];.apply_capable==false and .status=="review_only")' "$tmp/one-report.json" >/dev/null
jq -n '{schema_version:"1.0",examples:[{id:"a",before:{kind:"route",name:"old",method:"GET"},after:{kind:"route",name:"new",method:"GET"}},{id:"b",before:{kind:"route",name:"legacy",method:"GET"},after:{kind:"route",name:"current",method:"GET"}}],held_out:[{before:{kind:"route",name:"v1",method:"GET"},after:{kind:"route",name:"v2",method:"GET"},expected:true}]}' > "$tmp/multi.json"
bash generators/example_to_macro.sh --input "$tmp/multi.json" --output "$tmp/multi-report.json" --json >/dev/null
jq -e '.summary.candidates==1 and .summary.conflicting_signatures==0 and .metrics.held_out_precision>=0.95 and all(.candidates[];.apply_capable==false and (.parameters|length)>0 and (.edit_operations|length)>0)' "$tmp/multi-report.json" >/dev/null
jq -n '{schema_version:"1.0",examples:[{id:"a",before:{kind:"route",name:"old"},after:{kind:"route",name:"new"}},{id:"b",before:{kind:"route",name:"old"},after:{kind:"route",name:"new",method:"GET"}}]}' > "$tmp/conflict.json"
bash generators/example_to_macro.sh --input "$tmp/conflict.json" --output "$tmp/conflict-report.json" --json >/dev/null
jq -e '.summary.conflicting_signatures==1 and (.candidates|length)>=2 and all(.candidates[];.conflict==true)' "$tmp/conflict-report.json" >/dev/null
bash generators/structural_anti_unify.sh --input "$tmp/multi.json" --output "$tmp/anti.json" --json >/dev/null
jq -e '.compatible and (.parameters|length)>0' "$tmp/anti.json" >/dev/null
echo "  [OK] example synthesis review-only/conflict/held-out"
