#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/runtime-evidence.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
hash_id() { printf '%s' "$1" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}'; }
jq --arg source "runtime_trace_ingest" '
  def id_hash: (tojson|@base64);
  {schema_version:"2.0",ok:true,observations:([.[] | {edge_id:(.edge_id//"unattributed"),from:(.from//null),to:(.to//null),trace_id_hash:((.trace_id//"")|@base64),span_id_hash:((.span_id//"")|@base64),environment:(.environment//"unknown"),build:(.build//"unknown"),commit:(.commit//"unknown"),sampling:(.sampling//0),freshness:(.freshness//"unknown"),coverage:(.coverage//0),attribute_keys:([.attributes//{}|keys[]?]|sort),payload_retained:false,provenance:{source:$source,environment:(.environment//"unknown"),build:(.build//"unknown"),commit:(.commit//"unknown"),sampling:(.sampling//0),freshness:(.freshness//"unknown"),coverage:(.coverage//0)},static_uncertainty_preserved:true}]),summary:{sensitive_payload_retention:0,unattributed_edges:([.[]|select((.edge_id//"unattributed")=="unattributed")]|length),static_uncertainty_preserved:true,observations:length}}
' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Runtime evidence observations=\(.summary.observations) redaction=\(.summary.sensitive_payload_retention)"' "$OUT"; fi
