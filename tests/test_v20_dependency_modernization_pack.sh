#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{dependencies:[{ecosystem:"npm",kind:"mechanical"},{ecosystem:"pip",kind:"semantic"},{ecosystem:"go",kind:"configuration"},{ecosystem:"cargo",kind:"manual"},{ecosystem:"maven",kind:"mechanical"},{ecosystem:"gradle",kind:"semantic"}],constraints:{vulnerabilities:["CVE"],licenses:["MIT"]}}' > "$tmp/input.json"
bash generators/dependency_migration_plan.sh --input "$tmp/input.json" --output "$tmp/plan.json" --json >/dev/null
jq -e '.summary.ecosystem_migrations==6 and .summary.unlocked_lockfile_writes==0 and .lockfile.hermetic_locked' "$tmp/plan.json" >/dev/null
echo "  [OK] dependency modernization ecosystems=6 locked=1"
