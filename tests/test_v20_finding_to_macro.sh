#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '[
 {tool:"semgrep",rule_id:"route-handler",semantic_id:"api:route:server",path:"src/server.ts",line:10,message:"route handler drift",category:"behavior",severity:"error"},
 {tool:"codeql",rule_id:"route-handler",semantic_id:"api:route:server",path:"src/server.ts",line:10,message:"same route drift",category:"behavior",severity:"error"},
 {tool:"compiler",rule_id:"unused-import",semantic_id:"import:unused:server",path:"src/server.ts",line:2,message:"unused import",category:"import",severity:"warning"}
]' > "$tmp/findings.json"
bash generators/finding_normalize.sh --input "$tmp/findings.json" --output "$tmp/normalized.json" --json >/dev/null
jq -e '.summary.normalized==2 and .summary.deduplicated==1 and .summary.provenance_loss==0 and any(.findings[];.semantic_id=="api:route:server" and (.provenance|length)==2 and (.tools|length)==2)' "$tmp/normalized.json" >/dev/null
bash generators/finding_to_macro.sh --input "$tmp/findings.json" --output "$tmp/candidates.json" --json >/dev/null
jq -e '.summary.candidates==2 and .summary.apply_capable==0 and .summary.cross_tool_dedup_precision==1 and .summary.provenance_loss==0 and any(.candidates[];.decision=="simulation_and_human_approval" and (.evidence_requirements.counterexamples|length)>0)' "$tmp/candidates.json" >/dev/null
for tool in semgrep codeql compiler; do jq -e '.provenance_required==true' "adapters/findings/$tool.json" >/dev/null; done
echo "  [OK] finding normalization dedup/provenance/review-only candidates"
