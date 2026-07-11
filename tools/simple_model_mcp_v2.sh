#!/usr/bin/env bash
set -euo pipefail
read -r request
method="$(jq -r '.method//""' <<<"$request")"
id="$(jq '.id//1' <<<"$request")"
tool_list() {
  jq -n '{tools:[
    {name:"project_graph",description:"Return the stable project graph contract.",inputSchema:{type:"object",properties:{root:{type:"string"}}}},
    {name:"mql_plan",description:"Plan a deterministic MQL query without writes.",inputSchema:{type:"object",properties:{query:{type:"string"}}}},
    {name:"macro_simulate",description:"Simulate a macro and return proof obligations.",inputSchema:{type:"object",properties:{macro:{type:"string"}}}},
    {name:"proof_bundle",description:"Return content-addressed proof metadata.",inputSchema:{type:"object",properties:{digest:{type:"string"}}}},
    {name:"approval_status",description:"Inspect approval state; never grants approval.",inputSchema:{type:"object",properties:{plan_hash:{type:"string"}}}},
    {name:"adapter_facts",description:"Normalize facts contributed by a declared adapter.",inputSchema:{type:"object",properties:{adapter:{type:"string"}}}}
  ]}'
}
call_tool() {
  local name="$1" args="$2"
  case "$name" in
    project_graph) jq -n '{schema_version:"2.0",tool:"project_graph",decision:{action:"read",write:false},graph:{nodes:0,edges:0,content_addressed:true}}' ;;
    mql_plan) jq -n --arg query "$(jq -r '.query//""' <<<"$args")" '{schema_version:"2.0",tool:"mql_plan",decision:{action:"plan",write:false},query:$query,steps:[],deterministic:true}' ;;
    macro_simulate) jq -n --arg macro "$(jq -r '.macro//""' <<<"$args")" '{schema_version:"2.0",tool:"macro_simulate",decision:{action:"simulate",write:false},macro:$macro,proof:{rollback:true,provenance:true,approval_required:true},status:"review_only"}' ;;
    proof_bundle) jq -n --arg digest "$(jq -r '.digest//"empty"' <<<"$args")" '{schema_version:"2.0",tool:"proof_bundle",decision:{action:"inspect",write:false},digest:$digest,content_addressed:true,replayable:true}' ;;
    approval_status) jq -n --arg hash "$(jq -r '.plan_hash//""' <<<"$args")" '{schema_version:"2.0",tool:"approval_status",decision:{action:"inspect",write:false},plan_hash:$hash,approved:false,reason:"explicit_approval_required"}' ;;
    adapter_facts) jq -n --arg adapter "$(jq -r '.adapter//""' <<<"$args")" '{schema_version:"2.0",tool:"adapter_facts",decision:{action:"ingest",write:false},adapter:$adapter,capabilities:["facts","provenance"],facts:[]}' ;;
    *) jq -n --arg name "$name" '{error:"unknown_tool",name:$name}' ;;
  esac
}
case "$method" in
  initialize) result="$(jq -n '{protocolVersion:"2024-11-05",serverInfo:{name:"simple_model_v2",version:"2.0"},capabilities:{tools:{}}}')" ;;
  tools/list) result="$(tool_list)" ;;
  tools/call) result="$(call_tool "$(jq -r '.params.name//""' <<<"$request")" "$(jq -c '.params.arguments//{}' <<<"$request")")" ;;
  *) result="$(jq -n --arg method "$method" '{error:"unknown_method",method:$method}')" ;;
esac
jq -n --argjson id "$id" --argjson result "$result" '{jsonrpc:"2.0",id:$id,result:$result}'
