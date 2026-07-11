#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/macros/registry-v2.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$INPUT" ]] || { echo "--input is required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq -e 'type=="object" and .schema_version=="2.0" and (.macros|type)=="array" and (([.macros[].id]|length)==([.macros[].id]|unique|length))' "$INPUT" >/dev/null || { echo "malformed registry" >&2; exit 3; }
jq '
  . as $r | ($r.macros) as $macros | ([ $macros[].id ]|unique) as $ids
  | ([ $macros[] | select((.dependencies//[]) - $ids | length>0) | {id,dependencies}] ) as $unknown
  | def topo($remaining;$done):
      if ($remaining|length)==0 then $done
      else ([ $remaining[] | select((.dependencies//[]) - ($done|map(.id)) | length==0) ] | sort_by(.id)) as $ready
        | if ($ready|length)==0 then null else topo(($remaining-$ready);($done+$ready)) end end;
  (topo($macros;[])) as $order
  | [ $macros[] | . as $m | {id:$m.id,version:$m.version,status:($m.status//"active"),dependencies:($m.dependencies//[]),certificate:($m.certificate//{}),external_repositories:($m.external_repositories//[]),apply_eligible:(($m.status//"active")=="active" and ($m.certificate.trusted//false)==true and (($m.external_repositories//[])|unique|length)>=($r.policy.min_external_repositories//2))} ] as $entries
  | {schema_version:"2.0",ok:(($unknown|length)==0 and $order!=null),error:(if ($unknown|length)>0 then {code:"unknown_dependency",details:$unknown} elif $order==null then {code:"dependency_cycle"} else null end),resolution_order:($order//[]|map(.id)),macros:$entries,revocations:($r.revocations//[]),policy:($r.policy//{min_external_repositories:2}),summary:{macros:($entries|length),apply_eligible:([$entries[]|select(.apply_eligible)]|length),unresolved_conflicts:($unknown|length),cycles:(if $order==null then 1 else 0 end),revoked_apply_eligibility:([$entries[]|select(.status=="revoked" and .apply_eligible)]|length)}}
' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Registry macros=\(.summary.macros) eligible=\(.summary.apply_eligible)"' "$OUT"; fi
jq -e '.ok==true' "$OUT" >/dev/null
