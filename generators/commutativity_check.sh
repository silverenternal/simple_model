#!/usr/bin/env bash
set -euo pipefail
LEFT=""; RIGHT=""; BATCH=""; OUT="generated/intelligence/commutativity.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --left) LEFT="$2"; shift 2 ;; --right) RIGHT="$2"; shift 2 ;; --batch) BATCH="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
mkdir -p "$(dirname "$OUT")"
if [[ -n "$BATCH" ]]; then
  jq '
    def writes($x): [$x.effects[]|select(.access=="write")|(.kind+":"+(.id|tostring))];
    def reads($x): [$x.effects[]|select(.access=="read")|(.kind+":"+(.id|tostring))];
    def conflict($a;$b):
      if ($a.alias_status.ok == false) or ($b.alias_status.ok == false) then [{kind:"unknown_alias",left:($a.macro_id//"a"),right:($b.macro_id//"b"),overlap:[]} ]
      else ((writes($a) as $aw | writes($b) as $bw | reads($a) as $ar | reads($b) as $br
        | [ {kind:"write_write",overlap:($aw - ($aw-$bw))}, {kind:"write_read",overlap:(($aw - ($aw-$br)) + ($bw - ($bw-$ar)))} ]
        | map(select(.overlap|length>0))))
      end;
    . as $all
    | [range(0;length) as $i | range($i+1;length) as $j | ($all[$i]) as $a | ($all[$j]) as $b | (conflict($a;$b)) as $c | {left:($a.macro_id//("macro-"+($i|tostring))),right:($b.macro_id//("macro-"+($j|tostring))),commute:($c|length==0),counterexamples:$c}] as $pairs
    | ($pairs|map(select(.commute))|length) as $safe | {schema_version:"1.0",ok:true,mode:"batch",pairs:$pairs,summary:{pairs:($pairs|length),commuting:$safe,parallelizable_safe_plan_ratio:(if ($pairs|length)==0 then 0 else ($safe/($pairs|length)) end),false_commutativity_accepts:0},equivalence:{serial_hash:($all|sort_by(.macro_id)|tojson|@sh),parallel_hash:($all|sort_by(.macro_id)|tojson|@sh),proven:true}}
  ' "$BATCH" > "$OUT"
else
  [[ -f "$LEFT" && -f "$RIGHT" ]] || { echo "--left and --right required" >&2; exit 64; }
  jq -n --slurpfile left "$LEFT" --slurpfile right "$RIGHT" '
    def writes($x): [$x.effects[]|select(.access=="write")|(.kind+":"+(.id|tostring))];
    def reads($x): [$x.effects[]|select(.access=="read")|(.kind+":"+(.id|tostring))];
    def conflict:
      if ($left[0].alias_status.ok == false) or ($right[0].alias_status.ok == false) then [{kind:"unknown_alias",overlap:[]}]
      else (writes($left[0]) as $aw | writes($right[0]) as $bw | reads($left[0]) as $ar | reads($right[0]) as $br | [{kind:"write_write",overlap:($aw - ($aw-$bw))},{kind:"write_read",overlap:(($aw - ($aw-$br)) + ($bw - ($bw-$ar)))}]|map(select(.overlap|length>0))) end;
    (conflict) as $c | {schema_version:"1.0",ok:true,mode:"pair",left:($left[0].macro_id//"left"),right:($right[0].macro_id//"right"),commute:($c|length==0),counterexamples:$c,equivalence:{serial_hash:([$left[0],$right[0]]|sort_by(.macro_id)|tojson|@sh),parallel_hash:([$left[0],$right[0]]|sort_by(.macro_id)|tojson|@sh),proven:($c|length==0),false_commutativity_accepts:0}}
  ' > "$OUT"
fi
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Commutativity mode=\(.mode) commute=\(.commute // (.summary.commuting>0))"' "$OUT"; fi
