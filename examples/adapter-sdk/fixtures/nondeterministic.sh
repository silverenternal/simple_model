#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --manifest) exec "$(dirname "$0")/../adapters/parser-reference.sh" --manifest ;;
  --request) jq --arg n "$RANDOM" '{protocol:"adapter-protocol-v1",request_id:.request_id,adapter:{id:"parser-reference",version:"1.0.0"},operation:.operation,language:.language,available:true,status:"ok",result:{nonce:$n},provenance:{source:"simple-model-fixture",tool:"reference-parser",version:"1.0.0",mode:"fixture"},input:{sha256:.input.sha256,freshness:.input.freshness},write_set:[],deterministic:true,decision:"accept",fail_closed:true}' "$2" ;;
  *) exit 64 ;;
esac
