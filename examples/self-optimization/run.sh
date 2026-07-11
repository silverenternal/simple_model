#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
mkdir -p generated/self-optimization
bash generators/semantic_interface_ir.sh --root "$ROOT" --struct "$ROOT/struct.json" --output generated/self-optimization/interface-ir.json --json > generated/self-optimization/interface-ir.full.json
bash generators/optimization_score.sh --root "$ROOT" --struct "$ROOT/struct.json" --output-dir generated/self-optimization --json > generated/self-optimization/score.json
bash generators/optimization_plan.sh --root "$ROOT" --struct "$ROOT/struct.json" --output-dir generated/self-optimization --json > generated/self-optimization/plan.full.json
bash generators/macro_simulate.sh --plan generated/self-optimization/plan.json --output-dir generated/self-optimization --json > generated/self-optimization/simulation.full.json || true
jq -n \
  --slurpfile semantic generated/self-optimization/interface-ir.full.json \
  --slurpfile score generated/self-optimization/score.json \
  --slurpfile plan generated/self-optimization/plan.full.json \
  --slurpfile simulation generated/self-optimization/simulation.full.json \
  '($semantic[0] // {}) as $semantic
   | ($score[0] // {}) as $score
   | ($plan[0] // {}) as $plan
   | ($simulation[0] // {}) as $simulation
   | {schema_version:"1.0", ok:true, semantic:$semantic.summary, score:{score:$score.score,debt:$score.debt}, plan:$plan.summary, simulation:$simulation.summary}'
