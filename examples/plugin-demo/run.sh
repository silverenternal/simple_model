#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TARGET="$ROOT/examples/plugin-target-repo"
WRAPPER="$ROOT/plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh"
OUT="$ROOT/generated/plugin-demo"
mkdir -p "$OUT"

"$WRAPPER" --target-root "$TARGET" doctor --json > "$OUT/doctor.json"
"$WRAPPER" --target-root "$TARGET" ingest "$TARGET" "$OUT/struct.ingested.json" > "$OUT/ingest.json"
"$WRAPPER" --target-root "$TARGET" --struct "$TARGET/struct.json" audit > "$OUT/audit.json"
"$WRAPPER" --target-root "$TARGET" --struct "$TARGET/struct.json" interfaces > "$OUT/interfaces.json"
"$WRAPPER" --target-root "$TARGET" --struct "$TARGET/struct.json" facts > "$OUT/facts.json"
"$WRAPPER" --target-root "$TARGET" --struct "$TARGET/struct.json" pr-gate "$TARGET" src/api/server.ts > "$OUT/pr_gate.json" || true
"$WRAPPER" dashboard "$OUT/dashboard.html" >/dev/null

jq -n \
  --arg out "$OUT" \
  --argjson doctor "$(cat "$OUT/doctor.json")" \
  --argjson audit "$(cat "$OUT/audit.json")" \
  --argjson interfaces "$(cat "$OUT/interfaces.json")" \
  '{ok:$doctor.ok, output:$out, unmanaged:$audit.unmanaged_files, interfaces:($interfaces.summary // {})}'
