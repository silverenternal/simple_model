#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{modules:["api","domain","infra"],cycles:[]}' > "$tmp/input.json"
bash generators/boundary_plan.sh --input "$tmp/input.json" --output "$tmp/plan.json" --json >/dev/null
jq -e '.summary.apply_capable_macros==3 and .summary.new_dependency_cycles==0 and .summary.public_contract_shims? // true' "$tmp/plan.json" >/dev/null
jq -e '.new_dependency_cycles==0 and ([.macros[]|select(.apply_capable)]|length)==3' fixtures/macros/component-boundaries/fixtures.json >/dev/null
echo "  [OK] component boundaries apply_capable=3 cycles=0"
