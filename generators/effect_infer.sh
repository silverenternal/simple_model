#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT="generated/intelligence/macro-effects.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$INPUT" ]] || { echo "--input is required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
jq '
  def kinds: {files:"direct_file",symbols:"symbol",generated_outputs:"generated_output",contracts:"contract",tests:"test",build_targets:"build_target",runtime_surfaces:"runtime_surface"};
  def effect_set($section;$access):
    ($section // {}) as $s | [kinds|to_entries[] as $k | ($s[$k.key] // [])[] | {kind:$k.value,id:.,access:$access}];
  . as $m
  | ((effect_set($m.reads;"read") + effect_set($m.writes;"write")) | unique_by([.kind,.id,.access]) | sort_by(.kind,.id,.access)) as $effects
  | {schema_version:"1.0",macro_id:($m.macro_id // $m.id // "unknown"),effects:$effects,summary:{effects:($effects|length),reads:([$effects[]|select(.access=="read")]|length),writes:([$effects[]|select(.access=="write")]|length),kinds:([$effects[].kind]|unique|sort)},alias_status:{ok:(($m.unknown_aliases // [])|length==0),unknown:($m.unknown_aliases // []),cycles:[]},provenance:{source:"effect_infer",input_hash:"pending"}}
' "$INPUT" > "$OUT"
hash="$(jq -S -c 'del(.provenance.input_hash)' "$OUT" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
jq --arg hash "$hash" '.provenance.input_hash=$hash' "$OUT" > "$OUT.tmp"; mv "$OUT.tmp" "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Effects \(.macro_id) count=\(.summary.effects) writes=\(.summary.writes)"' "$OUT"; fi
