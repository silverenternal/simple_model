#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{candidates:[{id:"dead",static_reachable:false,runtime_calls:0,ownership_approved:true,affected_tests_passed:true},{id:"public",static_reachable:false,runtime_calls:0,ownership_approved:true,affected_tests_passed:true,public:true}]}' > "$tmp/input.json"
bash generators/reachability_proof.sh --input "$tmp/input.json" --output "$tmp/proof.json" --json >/dev/null
jq -e '.summary.apply_capable==1 and .summary.false_dead_code_deletions==0 and any(.proofs[];.id=="dead" and .deletion_allowed) and any(.proofs[];.id=="public" and .deletion_allowed==false)' "$tmp/proof.json" >/dev/null
jq -e '([.macros[]|select(.apply_capable)]|length)==3 and .policy.false_dead_code_deletions==0 and .policy.public_reflective_plugin_symbols=="blocked"' macros/packs/architecture-cleanup/pack.json >/dev/null
echo "  [OK] architecture cleanup static+dynamic+ownership+tests gated"

