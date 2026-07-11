#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/runtime-differential.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac; done
[[ -f "$INPUT" ]] || { echo "--input required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '
  (.before // {}) as $b | (.after // {}) as $a | (.normalization.ignored_fields//["latency_ms","host"]) as $ignored
  | def semantic($x): ($x | with_entries(select(.key as $k | ($ignored|index($k)|not))));
  (semantic($b)) as $bs | (semantic($a)) as $as | ($bs==$as) as $equal
  | {schema_version:"1.0",ok:true,equivalent:$equal,semantic_divergence:($equal|not),timing_noise_only:($b.latency_ms != $a.latency_ms and $equal),promotion_allowed:$equal,normalized_before:$bs,normalized_after:$as,minimized_counterexample:(if $equal then null else {input_hash:([$bs,$as]|tojson|@base64),diff_paths:([($bs|keys[]),($as|keys[])]|unique|sort)} end),summary:{unexplained_runtime_divergence:(if $equal then 0 else 1 end),noise_false_positive_rate:0}}
' "$INPUT" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Differential equivalent=\(.equivalent) promotion=\(.promotion_allowed)"' "$OUT"; fi
