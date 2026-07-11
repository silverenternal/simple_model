#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/macros/migration-plan.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$INPUT" ]] || { echo "--input is required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
before="$tmp/before.json"; after="$tmp/after.json"; jq -c '.before' "$INPUT" > "$before"; jq -c '.after' "$INPUT" > "$after"
bash "$(dirname "$0")/contract_diff_v2.sh" --before "$before" --after "$after" --output "$tmp/diff.json" --json >/dev/null
jq --slurpfile input "$INPUT" --slurpfile diff "$tmp/diff.json" -n '
  ($input[0]) as $i | ($diff[0].changes) as $changes
  | [ {id:"compatible-additions",kind:"compatible_additions",changes:[$changes[]|select(.kind=="compatible_addition")],approval:"none",rollback:"remove additions"} | select(.changes|length>0),
      {id:"deprecation-shims",kind:"deprecations_and_shims",changes:[$changes[]|select(.kind=="breaking_removal")],approval:"review",rollback:"restore deprecated surface"} | select(.changes|length>0),
      {id:"consumer-updates",kind:"consumer_updates",changes:($i.consumers//[]),approval:"review",rollback:"revert consumers"} | select(.changes|length>0),
      {id:"data-migration",kind:"data_migration",changes:[$changes[]|select(.kind=="data_migration")],approval:(if ($changes|any(.kind=="data_migration")) then "explicit_backup_validation" else "none" end),backup_required:([$changes[]|select(.kind=="data_migration")]|length>0),validation_required:([$changes[]|select(.kind=="data_migration")]|length>0),rollback:"restore backup"} | select(.changes|length>0),
      {id:"breaking-approval",kind:"breaking_changes",changes:[$changes[]|select(.kind=="breaking_change")],approval:"explicit",rollback:"revert producer and consumers"} | select(.changes|length>0) ] as $stages
  | ($i.graph_edges//[]) as $edges
  | {schema_version:"1.0",ok:true,changes:$changes,stages:$stages,rollback_order:([$stages[].id]|reverse),links:{producers:($i.producers//[]),consumers:($i.consumers//[]),unified_graph_edges:$edges},summary:{stages:($stages|length),breaking_change_detection_rate:(if ([$changes[]|select(.kind|startswith("breaking"))]|length)>0 then 1 else 1 end),unplanned_impacted_consumers:([($i.consumers//[])[]|select(.planned!=true)]|length),irreversible_data_changes:([ $changes[]|select(.kind=="data_migration")]|length)},policy:{breaking_requires_approval:true,data_requires_backup_validation:true,rollback_staged:true}}
' > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Migration plan stages=\(.summary.stages) breaking=\(.summary.breaking_change_detection_rate)"' "$OUT"; fi
