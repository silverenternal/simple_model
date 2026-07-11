#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -e '((.repositories|length)==12 and (.tasks|length)==120 and .chronological==true)' benchmarks/evolution-v2/manifest.json >/dev/null
bash generators/evolution_replay_v2.sh --manifest benchmarks/evolution-v2/manifest.json --output "$tmp/replay.json" --json >/dev/null
bash generators/evolution_replay_v2.sh --manifest benchmarks/evolution-v2/manifest.json --output "$tmp/replay.json" --resume --json >/dev/null
jq -e '.resumable and .tasks==120 and .regressions==0 and (.checkpoint_hash|length)==64' "$tmp/replay.json" >/dev/null
bash generators/evolution_score.sh --replay "$tmp/replay.json" --output "$tmp/score.json" --json >/dev/null
jq -e '.zero_regression_rate==1 and .macro_dominant_vs_manual.equal_budget' "$tmp/score.json" >/dev/null
echo "  [OK] evolution repos=12 tasks=120 resume/checkpoint zero_regression=1"
