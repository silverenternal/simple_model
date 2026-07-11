#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in
  --manifest) jq -n '{protocol:"adapter-protocol-v1",adapter:{id:"rewrite-reference",version:"1.0.0"},capabilities:["rewrite"],languages:["typescript"],provenance:{source:"simple-model-fixture",tool:"reference-rewriter",version:"1.0.0",mode:"fixture"},limits:{timeout_ms:1000,max_output_bytes:65536},sandbox:{required:true,network:false,write_paths:["generated/adapter-sdk"]},deterministic:true,optional:false}' ;;
  --request) jq '{protocol:"adapter-protocol-v1",request_id:.request_id,adapter:{id:"rewrite-reference",version:"1.0.0"},operation:.operation,language:.language,available:true,status:"ok",result:{schema_version:"1.0",edits:[]},provenance:{source:"simple-model-fixture",tool:"reference-rewriter",version:"1.0.0",mode:"fixture"},input:{sha256:.input.sha256,freshness:.input.freshness},write_set:["generated/adapter-sdk/preview.ts"],deterministic:true,decision:"accept",fail_closed:true,evidence:[{class:"rewrite",confidence:1.0,provenance:["reference-rewriter"],freshness:"current"}]}' "$2" ;;
  *) exit 64 ;;
esac
