#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --manifest) exec "$(dirname "$0")/../adapters/parser-reference.sh" --manifest ;;
  --request) jq '{protocol:"adapter-protocol-v1",request_id:.request_id,adapter:{id:"parser-reference",version:"1.0.0"},operation:.operation,language:.language,available:true,status:"ok",result:{nodes:[],edges:[]},provenance:{source:"simple-model-fixture",tool:"reference-parser",version:"1.0.0",mode:"fixture"},input:{sha256:.input.sha256,freshness:"stale"},write_set:[],deterministic:true,decision:"accept",fail_closed:true}' "$2" ;;
  *) exit 64 ;;
esac
