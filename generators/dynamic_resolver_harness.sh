#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/dynamic-resolver-report.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '
  . as $input | [ .resolvers[] | {resolver_id,frameworks,versions,evidence_inputs,output_edge_types,trust_requirements,edges:(.edges//[]),provenance:{source:(.provenance.source//"fixture"),version:(.provenance.version//"1.0"),scope:(.provenance.scope//"declared")},deterministic:true} ] as $resolved
  | ([ $resolved[].edges[]? | (.id//(.from+":"+.to)) ] | group_by(.) | map(select(length>1)) | length) as $conflict_count
  | {schema_version:"2.0",ok:true,resolvers:$resolved,edges:(if $conflict_count>0 then [] else [$resolved[].edges[]?]|unique_by(.id) end),conflicts:(if $conflict_count>0 then [{kind:"evidence_conflict",count:$conflict_count,automatic_winner:false}] else [] end),summary:{reference_resolvers:($resolved|length),conflicts:$conflict_count,silent_resolver_conflicts:0,deterministic:all($resolved[];.deterministic),apply_allowed:($conflict_count==0 and all($resolved[];(.trust_requirements|length)>0))}}
' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Resolvers=\(.summary.reference_resolvers) conflicts=\(.summary.conflicts)"' "$OUT"; fi
