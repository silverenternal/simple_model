#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --manifest) jq -n '{protocol:"adapter-protocol-v1",adapter:{id:"runtime-reference",version:"1.0.0"},capabilities:["runtime_evidence"],languages:["typescript"],provenance:{source:"simple-model-fixture",tool:"reference-runtime",version:"1.0.0",mode:"fixture"},limits:{timeout_ms:1000,max_output_bytes:65536},sandbox:{required:true,network:false,write_paths:[]},deterministic:true,optional:false}' ;;
  --request) jq '{protocol:"adapter-protocol-v1",request_id:.request_id,adapter:{id:"runtime-reference",version:"1.0.0"},operation:.operation,language:.language,available:true,status:"ok",result:{observations:[{event:"function.invoke",name:"answer",count:1}]},provenance:{source:"simple-model-fixture",tool:"reference-runtime",version:"1.0.0",mode:"fixture"},input:{sha256:.input.sha256,freshness:.input.freshness},write_set:[],deterministic:true,decision:"accept",fail_closed:true,evidence:[{class:"runtime",confidence:0.95,provenance:["reference-runtime"],freshness:"current"}]}' "$2" ;;
  *) exit 64 ;;
esac
