#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
SURFACES=""
SYMBOLS=""
OUT="generated/intelligence/dynamic-edges.json"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --surfaces) SURFACES="$2"; shift 2 ;;
    --symbols) SYMBOLS="$2"; shift 2 ;;
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

if [[ -z "$SURFACES" ]]; then
  SURFACES="$tmp/surfaces.json"
  bash "$SELF_DIR/dynamic_surface_scan.sh" --root "$ROOT" --struct "$STRUCT" --output "$SURFACES" --json >/dev/null
fi
if [[ -z "$SYMBOLS" ]]; then
  SYMBOLS="$tmp/symbols.json"
  bash "$SELF_DIR/symbol_identity.sh" --root "$ROOT" --struct "$STRUCT" --output "$SYMBOLS" --json >/dev/null
fi

report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --slurpfile surfaces "$SURFACES" --slurpfile symbols "$SYMBOLS" '
  def sid($s): ($s | gsub("[^A-Za-z0-9_.:-]"; "_"));
  ($surfaces[0].nodes // []) as $surfaces
  | ($symbols[0].symbols // []) as $symbols
  | [
      $surfaces[]? as $d
      | ($symbols | map(select(.path == ($d.path // ""))) | sort_by(-.confidence) | .[0] // null) as $s
      | ($d.risk_level // "dynamic_unverified") as $risk
      | (if ($d.verification_status // "") == "runtime_observed" or $risk == "dynamic_observed" then "runtime_observed"
         elif ($d.kind // "") == "generated_interface" then "generated"
         elif ($d.kind // "") == "env_gate" or ($d.kind // "") == "config_gate" then "config_derived"
         else "structural" end) as $eclass
      | (if $risk == "dynamic_unsafe" then "denied"
         elif $eclass == "runtime_observed" or $eclass == "generated" then "trusted"
         elif ($d.confidence // 0) >= 0.75 then "weak"
         else "stale" end) as $trust
      | {
          id:("dynedge:" + sid(($d.id // ($d.kind + ":" + $d.name + ":" + $d.path)))),
          kind:(if ($d.kind // "") == "route" then "route_binding"
                elif ($d.kind // "") == "di_binding" then "dependency_injection"
                elif ($d.kind // "") == "event_subscription" then "event_subscription"
                elif ($d.kind // "") == "generated_interface" then "generated_client"
                elif ($d.kind // "") == "plugin_registration" then "plugin_registration"
                elif ($d.kind // "") == "env_gate" then "env_gate"
                else "reflection_reference" end),
          from:(if $s == null then ("file:" + sid($d.path // "")) else $s.stable_id end),
          to:("dynamic:" + sid($d.id // ($d.name // ""))),
          path:($d.path // ""),
          name:($d.name // ""),
          confidence:([($d.confidence // 0.5), (if $s == null then 0.55 else $s.confidence end)] | min),
          evidence_class:$eclass,
          trust_state:$trust,
          blocks_safe_apply:($trust == "denied" or $trust == "stale"),
          evidence:{source:"dynamic_edge_resolver", surface:($d.evidence // {}), symbol:(if $s == null then null else {stable_id:$s.stable_id, tier:$s.parser_tier} end)}
        }
    ] as $edges
  | {
      schema_version:"1.0", ok:true, root:$root, struct:$struct,
      summary:{
        edges:($edges|length),
        trusted:($edges|map(select(.trust_state=="trusted"))|length),
        weak:($edges|map(select(.trust_state=="weak"))|length),
        stale:($edges|map(select(.trust_state=="stale"))|length),
        denied:($edges|map(select(.trust_state=="denied"))|length),
        blocks_safe_apply:($edges|map(select(.blocks_safe_apply))|length)
      },
      edges:($edges|sort_by(.id)),
      policy:{unobserved_dynamic_blocks_safe_apply:true, waiver_required_for_denied:true}
    }')

printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Dynamic edges=" + (.summary.edges|tostring) + " blocked=" + (.summary.blocks_safe_apply|tostring)' <<<"$report"; fi
