#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n --argjson names "$(printf '%s\n' dependency-injection reflection plugin-discovery generated-client route-registration event-bus orm-model decorator metaprogramming build-codegen graphql-schema protobuf-rpc | jq -R . | jq -s .)" '{resolvers:[$names[]|{resolver_id:.,frameworks:[.],versions:["1.0"],evidence_inputs:["struct.json"],output_edge_types:["dynamic_edge"],trust_requirements:["review"],edges:[{id:(.+":edge"),from:(.+":from"),to:(.+":to")}],provenance:{source:"fixture",version:"1.0",scope:"repo"}}]}' > "$tmp/input.json"
bash generators/dynamic_resolver_harness.sh --input "$tmp/input.json" --output "$tmp/report.json" --json >/dev/null
jq -e '.summary.reference_resolvers==12 and .summary.conflicts==0 and .summary.silent_resolver_conflicts==0 and .summary.deterministic and .summary.apply_allowed' "$tmp/report.json" >/dev/null
bash generators/dynamic_resolver_harness.sh --input "$tmp/input.json" --output "$tmp/replay.json" --json >/dev/null
cmp "$tmp/report.json" "$tmp/replay.json"
jq '.resolvers[1].edges[0].id="dependency-injection:edge"' "$tmp/input.json" > "$tmp/conflict.json"
bash generators/dynamic_resolver_harness.sh --input "$tmp/conflict.json" --output "$tmp/conflict-report.json" --json >/dev/null
jq -e '.summary.conflicts>0 and (.conflicts[0].automatic_winner==false) and .summary.apply_allowed==false' "$tmp/conflict-report.json" >/dev/null
echo "  [OK] dynamic resolver SDK reference_resolvers=12 conflicts fail-closed"
