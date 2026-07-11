#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/pack.json" <<'EOF'
{"pack_id":"fixture-pack","version":"2.0.0","source":{"repository":"fixture","commit":"abc"},"build_inputs":["adapter:v2"],"certificates":["cert-1"],"adapters":["typescript"],"dependencies":[],"permissions":{"write":false}}
EOF
bash generators/macro_pack_sign.sh --input "$tmp/pack.json" --output "$tmp/signed.json" --key-id key-v2 --key fixture-secret --json >/dev/null
bash generators/macro_pack_verify.sh --input "$tmp/signed.json" --key fixture-secret --output "$tmp/verified.json" --json >/dev/null
jq -e '.trusted and .can_simulate and .can_apply and .offline and .unsigned_trusted==false' "$tmp/verified.json" >/dev/null
jq '.permissions.write=true' "$tmp/signed.json" > "$tmp/tampered.json"
if bash generators/macro_pack_verify.sh --input "$tmp/tampered.json" --key fixture-secret --json >/dev/null 2>&1; then echo "tamper unexpectedly trusted" >&2; exit 1; fi
printf '{"revoked_keys":["key-v2"]}\n' > "$tmp/revoked.json"
if bash generators/macro_pack_verify.sh --input "$tmp/signed.json" --key fixture-secret --revocations "$tmp/revoked.json" --json >/dev/null 2>&1; then echo "revoked key unexpectedly trusted" >&2; exit 1; fi
echo "  [OK] macro pack signing offline verification tamper/revocation fail closed"
