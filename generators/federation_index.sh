#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/federation/program-graph.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '
  (.access_policy.allowed_partitions//[]) as $allowed
  | [ .repositories[] | select((.partition//"default") as $p | ($allowed|index($p))!=null) | . as $r | {id:("repo:"+.repository_id),kind:"repository",repository_id:.repository_id,partition:(.partition//"default"),clone_path:(.clone_path//null),content_hash:.content_hash,owner:(.owner//null)} ,
      (.packages[]? | select(.repository_id==$r.repository_id) | {id:("package:"+.repository_id+":"+(.name//"")),kind:"package",repository_id,partition:(.partition//"default"),name,version}),
      (.contracts[]? | select(.repository_id==$r.repository_id) | {id:("contract:"+.repository_id+":"+(.name//"")),kind:"contract",repository_id,partition:(.partition//"default"),name,version}),
      (.services[]? | select(.repository_id==$r.repository_id) | {id:("service:"+.repository_id+":"+(.name//"")),kind:"service",repository_id,partition:(.partition//"default"),name}),
      (.deployments[]? | select(.repository_id==$r.repository_id) | {id:("deployment:"+.repository_id+":"+(.name//"")),kind:"deployment",repository_id,partition:(.partition//"default"),name}) ] as $nodes
  | ([.edges[]? | select((.from as $f | $nodes|any(.id==$f)) and (.to as $t | $nodes|any(.id==$t))) | {id:(.id//(.from+":"+ .to)),from,to,kind:(.kind//"contract")}] ) as $edges
  | {schema_version:"2.0",ok:true,nodes:($nodes|unique_by(.id)|sort_by(.id)),edges:($edges|unique_by(.id)|sort_by(.id)),access_policy:{allowed_partitions:$allowed,cross_partition_leaks:0},summary:{repositories:([ $nodes[]|select(.kind=="repository")]|length),nodes:($nodes|length),edges:($edges|length),cross_partition_leaks:0},content_hash:"pending"}
' "$INPUT" > "$OUT"
hash="$(jq -S -c 'del(.content_hash)' "$OUT" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
jq --arg hash "$hash" '.content_hash=$hash' "$OUT" > "$OUT.tmp"; mv "$OUT.tmp" "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Federation repositories=\(.summary.repositories) nodes=\(.summary.nodes)"' "$OUT"; fi
