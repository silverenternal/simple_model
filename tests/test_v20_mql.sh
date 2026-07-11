#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bash generators/unified_program_graph.sh --root examples/plugin-target-repo --struct examples/plugin-target-repo/struct.json --output "$tmp/graph.json" --partitions "$tmp/parts" --json >/dev/null
jq -e 'length==30 and (map(.name)|unique|length)==30' specs/mql-migrated-checks.json >/dev/null
for i in $(seq 0 29); do
  check=$(jq ".[$i]" specs/mql-migrated-checks.json)
  jq -n --argjson check "$check" '{schema_version:"1.0",match:($check|del(.name)|if .node_name then .name=.node_name|del(.node_name) else . end),capture:"node",quantifier:"count",select:["id","kind","name"]}' > "$tmp/q$i.json"
  bash generators/mql_plan.sh --query "$tmp/q$i.json" --graph "$tmp/graph.json" --output "$tmp/p$i.json" --json >/dev/null
  bash generators/mql_execute.sh --plan "$tmp/p$i.json" --graph "$tmp/graph.json" --output "$tmp/r$i.json" --json >/dev/null
  expected=$(jq --argjson c "$check" '[.nodes[]|select((.kind|test($c.kind)) and (.name|test(($c.node_name//".*"))) and (.repository|test(($c.repository//".*"))) and (.component|test(($c.component//".*"))) and (.evidence.class|test(($c.evidence_class//".*"))) and (.evidence.confidence>=($c.confidence_gte//0)))]|length' "$tmp/graph.json")
  jq -e --argjson expected "$expected" '.value==$expected' "$tmp/r$i.json" >/dev/null
done
cp "$tmp/r0.json" "$tmp/replay-a.json"
bash generators/mql_execute.sh --plan "$tmp/p0.json" --graph "$tmp/graph.json" --output "$tmp/replay-b.json" --json >/dev/null
cmp "$tmp/replay-a.json" "$tmp/replay-b.json" || exit 1
jq -n '{schema_version:"1.0",match:{kind:"symbol"},capture:"root",traverse:{direction:"out",edge_kind:".*",min_depth:1,max_depth:2,to:{kind:".*"},capture:"target"},quantifier:"any"}' > "$tmp/traverse.json"
bash generators/mql_plan.sh --query "$tmp/traverse.json" --graph "$tmp/graph.json" --output "$tmp/traverse-plan.json" --json | jq -e '.cost.max_depth==2 and (.explain|length)>0'
jq '.traverse.max_depth=99' "$tmp/traverse.json" > "$tmp/unbounded.json"
if bash generators/mql_plan.sh --query "$tmp/unbounded.json" --graph "$tmp/graph.json" --output "$tmp/bad.json" --json >/dev/null 2>&1; then exit 1; fi
jq '.traverse.capture="root"' "$tmp/traverse.json" > "$tmp/ambiguous.json"
if bash generators/mql_plan.sh --query "$tmp/ambiguous.json" --graph "$tmp/graph.json" --output "$tmp/bad2.json" --json >/dev/null 2>&1; then exit 1; fi
echo "  [OK] MQL 30-check equivalence and fail-closed planning"
