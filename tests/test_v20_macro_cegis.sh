#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{macro_id:"route.macro",matcher_before:{kind:"function"},matcher_after:{kind:"function",name:"serve"},counterexamples:[{proof_obligation:"match_precision",input:{name:"wrong"},expected:{match:false},observed:{match:true},resolved:true},{proof_obligation:"rollback",input:{file:"src/a.ts"},expected:{restored:true},observed:{restored:false},resolved:true}]}' > "$tmp/input.json"
bash generators/macro_cegis.sh --input "$tmp/input.json" --output "$tmp/ledger.json" --json >/dev/null
jq -e '.ok and .summary.counterexamples==2 and .summary.counterexample_regressions==0 and .summary.automatic_safety_weakening==0 and .refinement.matcher_change=="narrow_or_equal" and .trusted_apply_allowed==false and all(.entries[]; (.counterexample_hash|length)==64 and .regression_fixture==true)' "$tmp/ledger.json" >/dev/null
jq -n '{macro_id:"route.macro",matcher_before:{kind:"function"},matcher_after:{kind:".*"},counterexamples:[{proof_obligation:"match_precision",input:{x:1},expected:false,observed:true,resolved:false},{proof_obligation:"match_precision",input:{x:2},expected:false,observed:true,resolved:false},{proof_obligation:"match_precision",input:{x:3},expected:false,observed:true,resolved:false}]}' > "$tmp/unresolved.json"
bash generators/macro_cegis.sh --input "$tmp/unresolved.json" --output "$tmp/unresolved-ledger.json" --json >/dev/null
jq -e '.state=="retired" and .summary.unresolved==3 and .refinement.matcher_change=="rejected_broadened_matcher"' "$tmp/unresolved-ledger.json" >/dev/null
echo "  [OK] CEGIS minimized/hash-addressed/demote-retire/fail-closed"
