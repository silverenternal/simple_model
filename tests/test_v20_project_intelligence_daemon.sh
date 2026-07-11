#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
root="$tmp/repo"; mkdir -p "$root/src" "$root/tests"; printf 'x\n' > "$root/src/a.ts"; printf 't\n' > "$root/tests/a.test.ts"
bash tools/simple_modeld.sh --root "$root" --state "$tmp/state.json" --branch main --once --json >/dev/null
jq -e '.policy.local_only and .policy.apply_allowed==false and .summary.applies==0 and .branch_reset==false' "$tmp/state.json" >/dev/null
bash tools/simple_modeld.sh --root "$root" --state "$tmp/state.json" --branch main --once --json >/dev/null
jq -e '.summary.stale_state_reads==0 and .partitions.graph.invalidated==false' "$tmp/state.json" >/dev/null
jq -n '{changed_files:["src/a.ts","tests/a.test.ts","docs/readme.md"]}' > "$tmp/events.json"
bash generators/watch_invalidate.sh --input "$tmp/events.json" --output "$tmp/invalidation.json" --json >/dev/null
jq -e '.coalesced and (.invalidated_partitions|index("graph")) and (.invalidated_partitions|index("tests")) and (.invalidated_partitions|index("drift"))' "$tmp/invalidation.json" >/dev/null
bash tools/simple_modeld.sh --root "$root" --state "$tmp/state.json" --branch feature --once --json >/dev/null
jq -e '.branch_reset==true and .policy.apply_allowed==false' "$tmp/state.json" >/dev/null
echo "  [OK] daemon local-only/crash-safe/incremental invalidation/branch reset"
