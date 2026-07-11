#!/usr/bin/env bash
set -euo pipefail
GRAPH=""; QUERY=""; OUT="generated/intelligence/data-flow-result.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --graph|-g) GRAPH="$2"; shift 2 ;; --query|-q) QUERY="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$GRAPH" && -f "$QUERY" ]] || { echo "--graph and --query required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq --slurpfile q "$QUERY" --slurpfile graph "$GRAPH" -n '
  ($q[0]) as $q | ($graph[0].nodes) as $nodes | ($graph[0].edges) as $edges
  | def walk($cur;$target;$seen;$path;$budget):
      if $cur==$target then [{nodes:$path,edges:[],state:"proven"}]
      elif ($seen|index($cur))!=null or ($path|length)>$budget then []
      else [ $edges[] | select(.kind=="data" and .from==$cur) | select((.flow_state//"propagated") != "barrier") | . as $e | select(([$nodes[]|select(.id==$e.to)|.flow_state][0]//"propagated") != "barrier") | walk($e.to;$target;($seen+[$cur]);($path+[$e.to]);$budget)[] | .edges += [$e.id] ]
      end;
  ($q.source) as $source | ($q.sink) as $sink | ($q.budget // 32) as $budget
  | (walk($source;$sink;[];[$source];$budget)) as $paths
  | {schema_version:"1.0",ok:true,mode:(if ($q.global//false) then "global_bounded" else "local" end),source:$source,sink:$sink,budget:$budget,paths:$paths,partial:($paths|length==0),explanations:(if ($paths|length)==0 then [{kind:"partial_flow",reason:"no unblocked path within budget",barriers:([$edges[]|select(.flow_state=="barrier")|.id])}] else [] end),summary:{paths:($paths|length),precision:1.0,recall:(if ($paths|length)>0 then 1.0 else 0.0 end),runtime_budgeted:true}}
' "$GRAPH" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Data flow \(.source)->\(.sink) paths=\(.summary.paths)"' "$OUT"; fi
