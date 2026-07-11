#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --manifest) jq -n '{protocol:"adapter-protocol-v1",adapter:{id:"query-reference",version:"1.0.0"},capabilities:["query"],languages:["typescript"],provenance:{source:"simple-model-fixture",tool:"reference-query",version:"1.0.0",mode:"fixture"},limits:{timeout_ms:1000,max_output_bytes:65536},sandbox:{required:true,network:false,write_paths:[]},deterministic:true,optional:false}' ;;
  --request) jq '{protocol:"adapter-protocol-v1",request_id:.request_id,adapter:{id:"query-reference",version:"1.0.0"},operation:.operation,language:.language,available:true,status:"ok",result:{matches:[{capture:"answer",kind:"function",name:"answer"}]},provenance:{source:"simple-model-fixture",tool:"reference-query",version:"1.0.0",mode:"fixture"},input:{sha256:.input.sha256,freshness:.input.freshness},write_set:[],deterministic:true,decision:"accept",fail_closed:true,evidence:[{class:"query",confidence:1.0,provenance:["reference-query"],freshness:"current"}]}' "$2" ;;
  *) exit 64 ;;
esac
