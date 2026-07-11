#!/usr/bin/env bash
set -euo pipefail
INPUT=""; KEY="simple-model-dev-key"; REVOCATIONS=""; OUT=""; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input|-i) INPUT="$2"; shift 2 ;;
    --key) KEY="$2"; shift 2 ;;
    --revocations) REVOCATIONS="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
canonical="$(jq -S -c '(. + {schema_version:(.schema_version//"2.0")}) | del(.content_hash,.signatures,.provenance)' "$INPUT")"
actual_hash="$(printf '%s' "$canonical" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
declared_hash="$(jq -r '.content_hash//""' "$INPUT")"; key_id="$(jq -r '.signatures[0].key_id//""' "$INPUT")"; declared_sig="$(jq -r '.signatures[0].signature//""' "$INPUT")"
expected_sig="$(printf '%s:%s:%s' "$key_id" "$actual_hash" "$KEY" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
revoked=0
if [[ -n "$REVOCATIONS" && -f "$REVOCATIONS" ]]; then jq -e --arg k "$key_id" '(.revoked_keys//[])|index($k)!=null' "$REVOCATIONS" >/dev/null && revoked=1 || true; fi
ok=1; reason="verified"
[[ "$actual_hash" == "$declared_hash" ]] || { ok=0; reason="content_hash_mismatch"; }
[[ "$declared_sig" == "$expected_sig" ]] || { ok=0; reason="signature_mismatch"; }
[[ "$revoked" == 0 ]] || { ok=0; reason="key_revoked"; }
if [[ -n "$OUT" ]]; then mkdir -p "$(dirname "$OUT")"; fi
report="$(jq -n --arg input "$INPUT" --arg reason "$reason" --arg key "$key_id" --arg actual "$actual_hash" --argjson ok "$ok" --argjson revoked "$revoked" '{schema_version:"2.0",ok:($ok==1),trusted:($ok==1),mode:(if $ok==1 then "trusted" else "inspect_only" end),input:$input,key_id:$key,actual_content_hash:$actual,reason:$reason,revoked:$revoked,unsigned_trusted:false,can_simulate:($ok==1),can_apply:($ok==1),offline:true}')"
if [[ -n "$OUT" ]]; then printf '%s\n' "$report" > "$OUT"; fi
if [[ "$JSON_OUT" == 1 ]]; then printf '%s\n' "$report"; else jq -r '"Pack verification trusted=\(.trusted) reason=\(.reason)"' <<<"$report"; fi
[[ "$ok" == 1 ]]
