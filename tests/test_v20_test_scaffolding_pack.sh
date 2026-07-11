#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{contracts:[{id:"api",graph_paths:["node:api"],assertion_source:"explicit_contract",label:"contract",labeled:true}]}' > "$tmp/contracts.json"
bash generators/test_obligation_mine.sh --input "$tmp/contracts.json" --output "$tmp/obligations.json" --json >/dev/null
jq -e '.summary.obligations==1 and .summary.unlabeled_characterization_assertions==0 and ((.obligations[0].graph_paths|length)==1)' "$tmp/obligations.json" >/dev/null
jq -n '{name:"api-fuzz",seed_corpus:["seed"],resource_limits:{timeout_ms:100,memory_mb:128},seed:42,toolchain:"pinned"}' > "$tmp/fuzz.json"
bash generators/fuzz_target_scaffold.sh --input "$tmp/fuzz.json" --output "$tmp/fuzz-out.json" --json >/dev/null
jq -e '.target.reproducibility.seed==42 and .target.resource_limits.timeout_ms==100 and .ai_leaf_task.typed and .ai_leaf_task.review_required' "$tmp/fuzz-out.json" >/dev/null
echo "  [OK] test scaffolding obligations/fuzz reproducibility"
