#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/macros/synthesized-macros.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$INPUT" ]] || { echo "--input is required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '
  def compare($a;$b;$path):
    if (($a|type) != ($b|type)) then [{path:$path,kind:"incompatible"}]
    elif (($a|type)=="object") then [((($a|keys)+($b|keys))|unique)[] as $k | if (($a|has($k)) and ($b|has($k))) then compare($a[$k];$b[$k];($path+[$k])) else [{path:($path+[$k]),kind:"incompatible"}] end] | add
    elif (($a|type)=="array") then if ($a|length)!=(($b|length)) then [{path:$path,kind:"incompatible"}] else [range(0;($a|length)) as $i | compare($a[$i];$b[$i];($path+[$i|tostring]))] | add end
    elif $a==$b then [] else [{path:$path,kind:"parameter",parameter:("param_"+(($path|join("_"))|gsub("[^A-Za-z0-9_]";"_"))),before:$a,after:$b}] end;
  def signature($e): [compare($e.before;$e.after;[])[] | select(.kind=="parameter" or .kind=="incompatible") | .path|join(".")]|sort;
  . as $input | ($input.examples // []) as $examples
  | [ $examples[] | select((.negative//false)|not) | . as $e | {id:($e.id//"example"),signature:signature($e),parameters:([compare($e.before;$e.after;[])[]|select(.kind=="parameter")|.parameter]|unique|sort),edits:compare($e.before;$e.after;[]),forbidden_matches:($e.forbidden_matches//[])} ] as $raw
  | ($raw|group_by(.signature|tojson)) as $groups
  | [ $groups[] | {id:("synthesized-"+(.[0].signature|tojson|@base64)),status:"review_only",apply_capable:false,examples:map(.id),parameters:(map(.parameters[])|unique|sort),required_context:["typed structural match","source hash","affected tests"],edit_operations:(map(.edits[]|select(.kind=="parameter"))|unique_by(.path)),postconditions:["lossless edit IR validates","idempotency proof required","equivalence contract required"],forbidden_matches:(map(.forbidden_matches[])|unique),conflict:false} ] as $candidates
  | ([ $raw[].signature|tojson ]|unique|length) as $signature_count
  | ($input.held_out // []) as $held
  | ([ $held[] | signature(.) as $sig | {matched:(([ $candidates[] | (.edit_operations|map(.path)|sort) | select(.==$sig) ]|length)>0),expected:(.expected//true)} ] ) as $held_results
  | ($held_results|map(select(.matched and .expected))|length) as $tp
  | ($held_results|map(select(.matched))|length) as $pred
  | ($held_results|map(select(.expected))|length) as $expected
  | {schema_version:"1.0",ok:true,candidates:(if $signature_count>1 then ($candidates|map(.conflict=true)) else $candidates end),summary:{examples:($examples|length),candidates:($candidates|length),single_example_apply_promotions:0,conflicting_signatures:(if $signature_count>1 then 1 else 0 end)},metrics:{held_out_precision:(if $pred==0 then 1 else ($tp/$pred) end),held_out_recall:(if $expected==0 then 1 else ($tp/$expected) end),single_example_apply_promotions:0},held_out:$held_results}
' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Synthesized candidates=\(.summary.candidates) conflicts=\(.summary.conflicting_signatures)"' "$OUT"; fi
