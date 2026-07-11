#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --manifest) jq -n '{protocol:"adapter-protocol-v1",adapter:{id:"optional-reference",version:"1.0.0"},capabilities:["parser"],languages:["typescript"],provenance:{source:"optional-backend",tool:"external-parser",version:"9.9.9",mode:"local"},limits:{timeout_ms:1000,max_output_bytes:65536},sandbox:{required:true,network:false,write_paths:[]},deterministic:true,optional:true}' ;;
  --request) jq '{protocol:"adapter-protocol-v1",request_id:.request_id,adapter:{id:"optional-reference",version:"1.0.0"},operation:.operation,language:.language,available:false,status:"unavailable",result:{reason:"optional backend is not installed"},provenance:{source:"optional-backend",tool:"external-parser",version:"9.9.9",mode:"local"},input:{sha256:.input.sha256,freshness:.input.freshness},write_set:[],deterministic:true,decision:"review_only",fail_closed:true,evidence:[{class:"unknown",confidence:0,provenance:["optional-backend"],freshness:"current"}]}' "$2" ;;
  *) exit 64 ;;
esac
