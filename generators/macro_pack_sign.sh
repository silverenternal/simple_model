#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT=""; KEY_ID="dev-v2"; KEY="simple-model-dev-key"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input|-i) INPUT="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --key-id) KEY_ID="$2"; shift 2 ;;
    --key) KEY="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
[[ -n "$OUT" ]] || { echo "--output required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
canonical="$(jq -S -c '(. + {schema_version:(.schema_version//"2.0")}) | del(.content_hash,.signatures,.provenance)' "$INPUT")"
content_hash="$(printf '%s' "$canonical" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
signature="$(printf '%s:%s:%s' "$KEY_ID" "$content_hash" "$KEY" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
jq --arg hash "$content_hash" --arg key_id "$KEY_ID" --arg signature "$signature" \
  '. + {schema_version:(.schema_version//"2.0"),content_hash:$hash,signatures:[{key_id:$key_id,algorithm:"sha256-keyed-envelope",signature:$signature}],provenance:{canonicalization:"jq-sort-keys",signed_at:"deterministic-fixture",offline_verifiable:true}}' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Signed \(.pack_id//"pack") hash=\(.content_hash) key=\(.signatures[0].key_id)"' "$OUT"; fi
