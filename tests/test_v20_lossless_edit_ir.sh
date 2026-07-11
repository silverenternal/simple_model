#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"; cd "$ROOT"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf 'alpha beta\ngamma\n' > "$tmp/source.txt"
hash="$( (sha256sum "$tmp/source.txt" 2>/dev/null || shasum -a 256 "$tmp/source.txt")|awk '{print $1}')"
jq -n --arg hash "$hash" '{schema_version:"1.0",source:"source.txt",source_hash:$hash,edits:[]}' > "$tmp/noop.json"
bash generators/edit_ir_diff.sh --ir "$tmp/noop.json" --root "$tmp" --output "$tmp/noop.out" --json >/dev/null
cmp "$tmp/source.txt" "$tmp/noop.out" || exit 1
jq -n --arg hash "$hash" '{schema_version:"1.0",source:"source.txt",source_hash:$hash,edits:[{id:"rename-beta",capture:{stable_id:"sym:text:beta",start:6,end:10,expected_hash:$hash},original:"beta",replacement:"BETA-LONG"},{id:"rename-gamma",capture:{stable_id:"sym:text:gamma",start:11,end:16,expected_hash:$hash},original:"gamma",replacement:"G"}]}' > "$tmp/edit.json"
bash generators/edit_ir_diff.sh --ir "$tmp/edit.json" --root "$tmp" --output "$tmp/applied.txt" --json >/dev/null
bash generators/edit_ir_inverse.sh --ir "$tmp/edit.json" --applied "$tmp/applied.txt" --output "$tmp/inverse.json" --json >/dev/null
cp "$tmp/applied.txt" "$tmp/applied-source.txt"; jq '.source="applied-source.txt"' "$tmp/inverse.json" > "$tmp/inverse-local.json"
bash generators/edit_ir_diff.sh --ir "$tmp/inverse-local.json" --root "$tmp" --output "$tmp/restored.txt" --json >/dev/null
cmp "$tmp/source.txt" "$tmp/restored.txt" || exit 1
jq '.edits += [{id:"overlap",capture:{stable_id:"sym:overlap",start:8,end:12,expected_hash:.source_hash},original:"ta b",replacement:"x"}]' "$tmp/edit.json" > "$tmp/overlap.json"
if bash generators/edit_ir_validate.sh --ir "$tmp/overlap.json" --root "$tmp" --json >/dev/null 2>&1; then exit 1; fi
jq '.source_hash="0000000000000000000000000000000000000000000000000000000000000000"' "$tmp/edit.json" > "$tmp/stale.json"
if bash generators/edit_ir_validate.sh --ir "$tmp/stale.json" --root "$tmp" --json >/dev/null 2>&1; then exit 1; fi
echo "  [OK] lossless edit IR"
