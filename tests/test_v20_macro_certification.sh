#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{schema_version:"1.0",id:"example.macro",version:"1.0.0",operator:"native_rewrite",write_paths:["src"],apply_capable:true}' > "$tmp/macro.json"
bash generators/macro_fixture_scaffold.sh --macro-id example.macro --output-dir "$tmp/fixtures" --json >/dev/null
bash tools/macro_certify.sh --macro "$tmp/macro.json" --fixtures "$tmp/fixtures" --output "$tmp/cert-a.json" --json >/dev/null
jq -e '.certified and .trusted and .apply_mode_allowed and (.certificate_hash|length)==64 and (.signature.value|length)==64 and (.required_fixture_kinds|length)==6 and all(.proof_obligations[];.passed==true)' "$tmp/cert-a.json" >/dev/null
bash tools/macro_certify.sh --macro "$tmp/macro.json" --fixtures "$tmp/fixtures" --output "$tmp/cert-b.json" --json >/dev/null
cmp "$tmp/cert-a.json" "$tmp/cert-b.json"
jq '.version="2.0.0"' "$tmp/macro.json" > "$tmp/macro-changed.json"
bash tools/macro_certify.sh --macro "$tmp/macro-changed.json" --fixtures "$tmp/fixtures" --output "$tmp/cert-changed.json" --json >/dev/null || true
jq -e '.inputs.content_hash != $hash' --arg hash "$(jq -r '.inputs.content_hash' "$tmp/cert-a.json")" "$tmp/cert-changed.json" >/dev/null
rm "$tmp/fixtures/negative.json"
if bash tools/macro_certify.sh --macro "$tmp/macro.json" --fixtures "$tmp/fixtures" --output "$tmp/cert-fail.json" --json >/dev/null 2>&1; then exit 1; fi
jq -e '.certified==false and .trusted==false and .apply_mode_allowed==false and any(.remediation[];.obligation=="fixture:negative")' "$tmp/cert-fail.json" >/dev/null
echo "  [OK] macro certification hash/signature/replay/fail-closed"
