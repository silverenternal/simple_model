#!/usr/bin/env bash
set -euo pipefail
PLAN=""; GRAPH="generated/intelligence/program-graph-v3.json"; OUT="generated/intelligence/mql-result.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --plan) PLAN="$2"; shift 2;; --graph) GRAPH="$2"; shift 2;; --output|-o) OUT="$2"; shift 2;; --json) JSON_OUT=1; shift;; *) echo "unknown arg: $1" >&2; exit 64;; esac; done
[[ -f "$PLAN" && -f "$GRAPH" ]] || { echo "--plan and --graph required" >&2; exit 64; }
jq --slurpfile p "$PLAN" '
  def matches($n;$p):
    (($p.kind//".*") as $r | ($n.kind//"")|test($r)) and
    (($p.name//".*") as $r | ($n.name//"")|test($r)) and
    (($p.repository//".*") as $r | ($n.repository//"")|test($r)) and
    (($p.component//".*") as $r | ($n.component//"")|test($r)) and
    (($p.evidence_class//".*") as $r | ($n.evidence.class//"")|test($r)) and
    (($n.evidence.confidence//0) >= ($p.confidence_gte//0));
  def step($ids;$t): [.edges[] as $e | select(($e.kind//"")|test($t.edge_kind)) | if $t.direction=="out" then select($ids|index($e.from))|$e.to else select($ids|index($e.to))|$e.from end] | unique | sort;
  def walk($ids;$t;$d): if $d>$t.max_depth then [] else (step($ids;$t)) as $next | (if $d >= $t.min_depth then $next else [] end) + walk($next;$t;$d+1) end;
  ($p[0].normalized_query) as $q
  | ([.nodes[] | . as $n | select(matches($n;$q.match)) | select(([$q.not[]? | matches($n;.)] | any) | not)] | sort_by(.id)) as $roots
  | (if $q.traverse then ([walk([$roots[].id];$q.traverse;1)[]] | unique) as $reachable | [.nodes[]|select($reachable|index(.id))|select(matches(.;$q.traverse.to))]|sort_by(.id) else [] end) as $targets
  | ([ $roots[] | {capture:$q.capture,node:.}] + (if $q.traverse then [$targets[]|{capture:$q.traverse.capture,node:.}] else [] end)) as $captures
  | {schema_version:"1.0",ok:true,plan_hash:$p[0].plan_hash,quantifier:$q.quantifier,
     value:(if $q.quantifier=="count" then ($roots|length) elif $q.quantifier=="any" then (($roots|length)>0) else (($roots|length)==(.summary.nodes)) end),
     summary:{roots:($roots|length),targets:($targets|length),captures:($captures|length)},captures:$captures}
' "$GRAPH" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"MQL result value=\(.value)"' "$OUT"; fi
