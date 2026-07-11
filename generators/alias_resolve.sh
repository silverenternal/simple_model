#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/alias-resolution.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$INPUT" ]] || { echo "--input is required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '
  (.aliases // []) as $aliases | (.unknown_aliases // []) as $unknown
  | def resolve($name;$seen):
      if ($seen|index($name)) != null then {terminal:$name,cycle:true,path:($seen+[$name])}
      else ([ $aliases[] | select(.from==$name) | .to ][0]) as $next
        | if $next == null then {terminal:$name,cycle:false,path:($seen+[$name])}
          else resolve($next;($seen+[$name])) end end;
  ([ $aliases[].from, $aliases[].to ] | unique | sort) as $names
  | ([$names[] as $name | {name:$name,resolution:resolve($name;[])}]) as $resolved
  | {schema_version:"1.0",ok:(($unknown|length)==0 and ([$resolved[].resolution|select(.cycle)]|length)==0),unknown:$unknown,cycles:([$resolved[]|select(.resolution.cycle)]),resolved:$resolved,summary:{aliases:($aliases|length),unknown:($unknown|length),cycles:([$resolved[].resolution|select(.cycle)]|length)}}
' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Aliases=\(.summary.aliases) unknown=\(.summary.unknown) cycles=\(.summary.cycles)"' "$OUT"; fi
jq -e '.ok==true' "$OUT" >/dev/null
