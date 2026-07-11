#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
FACTS=""
TIERS=""
OUT="generated/intelligence/symbol-index.json"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --facts) FACTS="$2"; shift 2 ;;
    --tiers) TIERS="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
STRUCT="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [[ -z "$FACTS" ]]; then
  FACTS="$tmp/facts.json"
  bash "$SELF_DIR/tree_sitter_scan.sh" --root "$ROOT" --output "$FACTS" --json >/dev/null
fi
if [[ -z "$TIERS" ]]; then
  TIERS="$tmp/tiers.json"
  bash "$SELF_DIR/parser_tier_registry.sh" --root "$ROOT" --output "$TIERS" --json >/dev/null
fi

report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --slurpfile facts "$FACTS" --slurpfile tiers "$TIERS" '
  def sha($s): ($s | @base64);
  def sid($s): ($s | gsub("[^A-Za-z0-9_.:-]"; "_"));
  ($facts[0].facts // []) as $facts
  | ($tiers[0].files // []) as $tiers
  | ($tiers | map({key:.path, value:.}) | from_entries) as $tier_by_path
  | [
      $facts[]?
      | select(.from|not)
      | . as $f
      | ($tier_by_path[$f.path] // {}) as $tier
      | (($f.language // "unknown") + ":" + ($f.path|split("/")[:-1]|join(".")) + ":" + ($f.name // "") + ":" + ($f.kind // "") + ":" + (($f.line_start // 0)|tostring)) as $sig
      | {
          id:("symbol:" + ($f.path|gsub("[^A-Za-z0-9_.:-]"; "_")) + ":" + (($f.line_start // 0)|tostring) + ":" + ($f.name // "")),
          stable_id:("sym:" + (sid(($f.language // "unknown") + ":" + (($f.path|split("/")[:-1]|join(".")) // "") + ":" + ($f.name // "") + ":" + ($f.kind // "")))),
          language:($f.language // "unknown"),
          kind:($f.kind // "symbol"),
          name:($f.name // ""),
          path:$f.path,
          line_start:($f.line_start // 0),
          package:($f.path|split("/")[:-1]|join(".")),
          qualified_name:(($f.path|split("/")[:-1]|join(".")) + "." + ($f.name // "")),
          structural_signature:$sig,
          confidence:([($f.confidence // 0.5), ($tier.confidence // 0.5)] | min),
          parser_tier:($tier.tier // "structural_fallback"),
          invalidation_key:($tier.invalidation_key // $f.hash // ""),
          evidence:{source:"symbol_identity", parser:($f.parser // "unknown"), tier:($tier.tier // "structural_fallback")}
        }
    ] as $symbols
  | ($symbols | group_by(.stable_id) | map(select(length > 1) | {stable_id:.[0].stable_id, paths:map(.path)|unique, names:map(.name)|unique}) | map(select((.paths|length) > 1 and (.names|length) > 1))) as $conflicts
  | {
      schema_version:"1.0", ok:($conflicts|length == 0), root:$root, struct:$struct,
      summary:{symbols:($symbols|length), conflicts:($conflicts|length), low_confidence:($symbols|map(select(.confidence < 0.8))|length)},
      symbols:($symbols|sort_by(.stable_id,.path,.line_start)),
      conflicts:$conflicts,
      policy:{conflict_policy:"review_required", moved_file_identity:true}
    }')

printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Symbol index symbols=" + (.summary.symbols|tostring) + " conflicts=" + (.summary.conflicts|tostring)' <<<"$report"; fi
