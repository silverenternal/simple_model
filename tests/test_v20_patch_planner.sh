#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
root="$tmp/repo"; mkdir -p "$root/src" "$root/generated"
printf 'import {x} from "x";\nexport function handler() { return x; }\n' > "$root/src/app.ts"
printf 'export const protectedValue = 1;\n' > "$root/src/protected.ts"
printf 'export const generated = 1;\n' > "$root/generated/client.ts"
mkdir -p "$root/.simple_model"
jq -n '{paths:["src/protected.ts"]}' > "$root/.simple_model/protected.json"
cp benchmarks/patch-minimality/patch.json "$tmp/patch.json"
bash generators/style_profile.sh --root "$root" --output "$tmp/profile.json" --json >/dev/null
jq -e '.summary.protected>=1 and any(.files[];.path=="src/app.ts" and .formatter=="prettier_or_preserve") and any(.files[];.path=="generated/client.ts" and .generated==true)' "$tmp/profile.json" >/dev/null
bash generators/patch_planner.sh --root "$root" --patch "$tmp/patch.json" --profile "$tmp/profile.json" --output "$tmp/plan.json" --json >/dev/null
jq -e '.ok and .summary.selected_files==1 and .summary.blocked_edits==2 and .summary.protected_region_writes==1 and .summary.unnecessary_line_change_ratio==0 and (.files[0].formatter_scope.start_line==1 and .files[0].formatter_scope.end_line==2) and (.alternatives|length)==2' "$tmp/plan.json" >/dev/null
jq -e 'all(.files[]; ((.generated//false)|not) and ((.vendored//false)|not) and ((.ignored//false)|not))' "$tmp/plan.json" >/dev/null
echo "  [OK] patch planner minimality ratio=0 protected_writes=0"
