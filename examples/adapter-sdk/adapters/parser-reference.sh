#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --manifest) jq -n '{protocol:"adapter-protocol-v1",adapter:{id:"parser-reference",version:"1.0.0"},capabilities:["parser"],languages:["typescript"],provenance:{source:"simple-model-fixture",tool:"reference-parser",version:"1.0.0",mode:"fixture"},limits:{timeout_ms:1000,max_output_bytes:65536},sandbox:{required:true,network:false,write_paths:[]},deterministic:true,optional:false}' ;;
  --request) jq '{protocol:"adapter-protocol-v1",request_id:.request_id,adapter:{id:"parser-reference",version:"1.0.0"},operation:.operation,language:.language,available:true,status:"ok",result:{nodes:[{id:"node:function:answer",kind:"function",name:"answer"}],edges:[]},provenance:{source:"simple-model-fixture",tool:"reference-parser",version:"1.0.0",mode:"fixture"},input:{sha256:.input.sha256,freshness:.input.freshness},write_set:[],deterministic:true,decision:"accept",fail_closed:true,evidence:[{class:"parsed",confidence:1.0,provenance:["reference-parser"],freshness:"current"}]}' "$2" ;;
  *) exit 64 ;;
esac
