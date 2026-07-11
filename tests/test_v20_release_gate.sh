#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bash generators/release_slo_v2.sh --output "$tmp/readiness.json" --json >/dev/null
jq -e '.schema_version=="2.0" and .ok and .summary.release_gate_failures==0 and .summary.program_targets_met==1.0 and .checks.program_targets and .checks.external_evidence and .checks.held_out_evidence and .checks.gauntlet and .checks.supply_chain and .checks.plugin_signed_summaries and .program_targets.apply_capable_macros>=24 and .program_targets.simulate_capable_macros>=40 and .program_targets.macro_families>=16 and .program_targets.false_safe_apply==0 and (.release_hash|length)==64' "$tmp/readiness.json" >/dev/null
mkdir -p generated/releases
cp "$tmp/readiness.json" generated/releases/v2-production-readiness.json
echo "  [OK] v2 release gate targets=1.0 external+heldout hermetic supply-chain plugin summaries"
