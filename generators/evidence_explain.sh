#!/usr/bin/env bash
set -euo pipefail
LEDGER="generated/intelligence/evidence-ledger.json"
SUBJECT=""
JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --ledger) LEDGER="$2"; shift 2;; --subject) SUBJECT="$2"; shift 2;; --json) JSON_OUT=1; shift;; *) echo "unknown arg: $1" >&2; exit 64;; esac; done
[[ -n "$SUBJECT" ]] || { echo "--subject required" >&2; exit 64; }
report="$(jq --arg subject "$SUBJECT" '
  first(.subjects[]|select(.subject==$subject)) // {subject:$subject,state:"unknown",verdict:"unknown",facts:[]}
  | . as $s
  | {schema_version:"1.0",ok:true,subject:$subject,state:.state,verdict:.verdict,
     blockers:(if .state=="conflict" then ["contradictory_current_evidence"] elif .state=="stale" then ["all_evidence_stale"] elif .state=="unknown" then ["no_evidence"] else [] end),
     minimal_evidence_needed:(if .state=="conflict" then {action:"invalidate_or_reproduce",classes:([.facts[].class]|unique),count:1} elif .state=="stale" then {action:"refresh",classes:([.facts[].class]|unique),count:1} elif .state=="unknown" then {action:"collect",classes:["parsed","runtime"],count:1} else {action:"none",classes:[],count:0} end),
     provenance:(.provenance // []),invalidation_keys:(.invalidation_keys // [])}' "$LEDGER")"
printf '%s\n' "$report"
