#!/usr/bin/env bash
set -euo pipefail
jq -e '.status=="certified" and ([.macros[]|select(.apply_capable)]|length)==4 and .policy.missed_static_references==0' macros/packs/symbol-lifecycle/pack.json >/dev/null
jq -e '.external_fixture and .missed_static_references==0 and .dynamic_references.trusted_resolver' fixtures/macros/symbol-lifecycle/fixtures.json >/dev/null
echo "  [OK] symbol lifecycle apply_capable=4 missed_static_references=0"
