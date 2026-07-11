#!/usr/bin/env bash
set -euo pipefail
QUERY=""; GRAPH=""; OUT="generated/intelligence/structural-match.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --query|-q) QUERY="$2"; shift 2 ;;
    --graph|-g) GRAPH="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -f "$QUERY" && -f "$GRAPH" ]] || { echo "--query and --graph required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
query_hash="$(jq -S -c . "$QUERY" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
graph_hash="$(jq -S -c '{nodes,edges}' "$GRAPH" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
jq --arg qh "$query_hash" --arg gh "$graph_hash" '
  def subset($actual;$wanted):
    if $wanted == null then true
    elif ($wanted|type) == "object" then all($wanted|to_entries[]; . as $e | subset(($actual[$e.key] // null); $e.value))
    else $actual == $wanted end;
  def structural_match($n;$p):
    (subset($n;$p)) and
    (subset(($n.syntax // {});($p.syntax // null))) and
    (subset(($n.symbol // {});($p.symbol // null))) and
    (if $p.evidence_class == null then true else ($n.evidence.class // "") == $p.evidence_class end) and
    (if $p.confidence_gte == null then true else (($n.evidence.confidence // 0) >= $p.confidence_gte) end);
  . as $input
  | ($query[0] // {}) as $query
  | ($query.match // {}) as $pattern
  | [($input.nodes // [])[] | select(structural_match(.;$pattern))] as $candidates
  | [ $candidates[] | {capture:($query.capture // "node"),node_id:(.id // ""),stable_id:(.symbol_id // .id // ""),typed:{kind:(.kind // ""),name:(.name // ""),language:(.language // (.evidence.language // ""))},symbol_identity:{symbol_id:(.symbol_id // .id // ""),qualified_name:(.qualified_name // .name // ""),repository:(.repository // ""),component:(.component // "")},style_context:{indent:(.style.indent // null),quote:(.style.quote // null),line_ending:(.style.line_ending // null)}} ] as $matches
  | ([ $matches[].stable_id ] | group_by(.) | map(select(length > 1)) | length > 0) as $duplicate_identity
  | ((($query.capture_policy // "unique") == "unique") and ($matches|length > 1)) as $multiple_unique
  | {schema_version:"1.0",ok:true,query_hash:$qh,graph_hash:$gh,matches:$matches,summary:{matches:($matches|length),candidate_count:($candidates|length),ambiguous:($duplicate_identity or $multiple_unique),apply_allowed:(($matches|length)>0 and (($duplicate_identity or $multiple_unique)|not))},diagnostics:(if $duplicate_identity then [{code:"duplicate_stable_identity",severity:"error",message:"multiple nodes resolve to the same stable identity"}] elif $multiple_unique then [{code:"multiple_capture_targets",severity:"error",message:"unique capture matched more than one node"}] else [] end)}
' --slurpfile query "$QUERY" "$GRAPH" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Structural match matches=\(.summary.matches) ambiguous=\(.summary.ambiguous) apply=\(.summary.apply_allowed)"' "$OUT"; fi
jq -e '.ok==true' "$OUT" >/dev/null
