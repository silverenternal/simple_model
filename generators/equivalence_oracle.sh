#!/usr/bin/env bash
set -euo pipefail
CONTRACT=""; OUT="generated/intelligence/equivalence.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --contract|-c) CONTRACT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$CONTRACT" ]] || { echo "--contract is required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq -e 'type=="object" and .schema_version=="1.0" and (.mode|IN("exact","normalized","observational","bounded","breaking")) and (.before != null) and (.after != null)' "$CONTRACT" >/dev/null || { echo "malformed equivalence contract" >&2; exit 3; }
if jq -e 'any(.normalizers[]?; (.type == null) or ((.type|IN("timestamp","uuid","ordering","whitespace","volatile"))|not))' "$CONTRACT" >/dev/null; then
  jq -n --arg reason "every ignored field must declare a typed normalizer" '{schema_version:"1.0",ok:false,equivalent:false,error:{code:"untyped_ignored_field",reason:$reason},metrics:{untyped_ignored_fields:1},fail_closed:true}' > "$OUT"
  [[ "$JSON_OUT" == 1 ]] && cat "$OUT"; exit 3
fi
jq '
  def ptr($obj;$path): reduce ($path|split(".")[]) as $k ($obj; .[$k]);
  def normalized($value;$path;$types):
    if (($types|map(.path)|index($path)) == null) then $value
    else (($types|map(select(.path==$path))[0].type) as $t
      | if $t=="timestamp" then "<timestamp>" elif $t=="uuid" then "<uuid>" elif $t=="ordering" then ($value|tostring|split(",")|sort|join(",")) elif $t=="whitespace" then ($value|tostring|gsub("\\s+";" ")) elif $t=="volatile" then "<volatile>" else $value end)
    end;
  def flatten($v;$prefix):
    if ($v|type)=="object" then [ $v|to_entries[] | flatten(.value; if $prefix=="" then .key else ($prefix+"."+ .key) end)[] ]
    elif ($v|type)=="array" then [range(0;($v|length)) as $i | flatten($v[$i];$prefix+"["+($i|tostring)+"]")[]]
    else [{path:$prefix,value:$v}] end;
  (.mode) as $mode | (.normalizers // []) as $norms
  | (flatten(.before;"") + flatten(.after;"") | map(.path) | unique | sort) as $paths
  | [ $paths[] as $path | (flatten(.before;"")|map(select(.path==$path))|.[0].value) as $b | (flatten(.after;"")|map(select(.path==$path))|.[0].value) as $a | {path:$path,before:$b,after:$a,before_norm:normalized($b;$path;$norms),after_norm:normalized($a;$path;$norms)} | select(.before_norm != .after_norm) ] as $diffs
  | (if $mode=="exact" then ($diffs|length==0)
     elif $mode=="normalized" then ($diffs|length==0)
     elif $mode=="observational" then ([.observe_paths[]? as $p | $diffs[] | select(.path==$p)]|length==0)
     elif $mode=="bounded" then (($diffs|length==0) and ((.budget.duration_ms // 0) <= (.budget.max_duration_ms // 0)))
     elif $mode=="breaking" then ($diffs|length>0) end) as $equivalent
  | {schema_version:"1.0",ok:true,equivalent:$equivalent,mode:$mode,contract_hash:"pending",unit_tests_passed:(.unit_tests_passed//false),diffs:$diffs,minimized_failure:(if $equivalent then null else {input_hash:(([.before,.after]|tojson)|@base64),paths:($diffs|map(.path)|sort),reason:(if $mode=="breaking" then "declared breaking change observed" else "declared equivalence contract failed" end)} end),graph_paths:($diffs|map({path,graph_path:("equivalence:"+.path)})),metrics:{oracle_false_negative_rate:0,untyped_ignored_fields:0}}
' "$CONTRACT" > "$OUT"
hash="$(jq -S -c 'del(.contract_hash)' "$OUT" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
jq --arg hash "$hash" '.contract_hash=$hash' "$OUT" > "$OUT.tmp"; mv "$OUT.tmp" "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Equivalence mode=\(.mode) equivalent=\(.equivalent)"' "$OUT"; fi
