#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
repos="$(jq -n '[range(0;60)|{repository_id:("repo-"+(.|tostring)),clone_path:("/tmp/clone-"+(.|tostring)),partition:(if (.%2)==0 then "team-a" else "team-b" end),content_hash:(("hash-"+(.|tostring))),owner:"owner"}]')"
jq -n --argjson repos "$repos" '{repositories:$repos,packages:[$repos[]|{repository_id:.repository_id,name:"pkg",version:"1.0"}],contracts:[$repos[]|{repository_id:.repository_id,name:"api",version:"v1"}],services:[$repos[]|{repository_id:.repository_id,name:"svc"}],deployments:[$repos[]|{repository_id:.repository_id,name:"deploy"}],access_policy:{allowed_partitions:["team-a"]},edges:[]}' > "$tmp/input.json"
bash generators/federation_index.sh --input "$tmp/input.json" --output "$tmp/graph.json" --json >/dev/null
jq -e '.summary.repositories==30 and .summary.cross_partition_leaks==0 and (.content_hash|length)==64 and all(.nodes[];.partition=="team-a")' "$tmp/graph.json" >/dev/null
bash generators/federation_incremental.sh --input "$tmp/input.json" --previous "$tmp/graph.json" --output "$tmp/inc.json" --json >/dev/null
jq -e '.rescanned_repositories==0 and .cross_partition_leaks==0' "$tmp/inc.json" >/dev/null
jq '.repositories[0].clone_path="/different/fork/path"' "$tmp/input.json" > "$tmp/clone.json"
bash generators/federation_index.sh --input "$tmp/clone.json" --output "$tmp/clone-graph.json" --json >/dev/null
jq -e --slurpfile a "$tmp/graph.json" '([.nodes[]|select(.kind=="repository")|.id]|sort)==([$a[0].nodes[]|select(.kind=="repository")|.id]|sort)' "$tmp/clone-graph.json" >/dev/null
echo "  [OK] federation repositories=60 access_leaks=0 incremental_rescan=0"
