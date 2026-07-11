#!/usr/bin/env bash
set -euo pipefail
PLAN=""; OUT="generated/intelligence/probe-budget.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --plan|-p) PLAN="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$PLAN" ]] || { echo "--plan required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
if jq -e 'any(.probes[]; (.read_only!=true) or (.network!=false) or any(.argv[]; test("[;&|$()<>]")))' "$PLAN" >/dev/null; then
  jq -n '{schema_version:"1.0",ok:false,decision:"reject",error:{code:"unsafe_probe",reason:"probe is not read-only, uses network, or contains shell metacharacters"},unsafe_probe_executions:0,fail_closed:true}' > "$OUT"
  [[ "$JSON_OUT" == 1 ]] && cat "$OUT"; exit 3
fi
jq '(.probes|length) as $n | if $n > .budget.max_probes then {schema_version:"1.0",ok:false,decision:"review_only",error:{code:"probe_budget_exceeded"},probes:$n,unsafe_probe_executions:0,fail_closed:true} else {schema_version:"1.0",ok:true,decision:"allow",probes:$n,timeout_ms:.budget.timeout_ms,network_allowlist:.policy.network_allowlist,unsafe_probe_executions:0,fail_closed:true} end' "$PLAN" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Probe budget decision=\(.decision) probes=\(.probes)"' "$OUT"; fi
