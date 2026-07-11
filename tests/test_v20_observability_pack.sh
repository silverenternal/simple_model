#!/usr/bin/env bash
set -euo pipefail
jq -e '.semantic_convention_version=="1.27.0" and .sensitive_policy=="block_without_explicit_redaction"' specs/telemetry-contract.json >/dev/null
jq -e '.duplicate_instrumentation_rate==0 and .semantic_convention_compliance==1 and .sensitive_attribute_blocked and .stable_graph_node_mapping' fixtures/macros/observability/fixtures.json >/dev/null
echo "  [OK] observability conventions=1.0 duplicate_rate=0 sensitive blocked"
