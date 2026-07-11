#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/macros/anti-unify.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$INPUT" ]] || { echo "--input is required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '
  def compare($a;$b;$path):
    if (($a|type) != ($b|type)) then [{path:$path,kind:"incompatible",before:$a,after:$b}]
    elif (($a|type)=="object") then [((($a|keys)+($b|keys))|unique)[] as $k | if (($a|has($k)) and ($b|has($k))) then compare($a[$k];$b[$k];($path+[$k])) else [{path:($path+[$k]),kind:"incompatible",reason:"missing field"}] end] | add
    elif (($a|type)=="array") then if ($a|length)!=(($b|length)) then [{path:$path,kind:"incompatible",reason:"array length"}] else [range(0;($a|length)) as $i | compare($a[$i];$b[$i];($path+[$i|tostring]))] | add end
    elif $a==$b then [] else [{path:$path,kind:"parameter",before:$a,after:$b,parameter:("param_"+(($path|join("_"))|gsub("[^A-Za-z0-9_]";"_")))}] end;
  . as $input | ($input.examples // []) as $examples
  | if ($examples|length)<2 then {schema_version:"1.0",ok:true,compatible:true,parameters:[],differences:[],conflicts:[],evidence_examples:($examples|length)}
    else (compare($examples[0].before;$examples[1].before;[]) + compare($examples[0].after;$examples[1].after;[])) as $diffs
    | {schema_version:"1.0",ok:true,compatible:([$diffs[]|select(.kind=="incompatible")]|length==0),parameters:([$diffs[]|select(.kind=="parameter")|.parameter]|unique|sort),differences:$diffs,conflicts:([$diffs[]|select(.kind=="incompatible")]),evidence_examples:($examples|length)} end
' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Anti-unify compatible=\(.compatible) parameters=\(.parameters|length)"' "$OUT"; fi
