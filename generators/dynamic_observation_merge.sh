#!/usr/bin/env bash
set -euo pipefail

SURFACES="generated/intelligence/dynamic-surfaces.json"
OBSERVATIONS="generated/intelligence/runtime-observations.json"
OUT="generated/intelligence/dynamic-surfaces.observed.json"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --surfaces) SURFACES="$2"; shift 2 ;;
    --observations) OBSERVATIONS="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    -h|--help) echo "dynamic_observation_merge.sh --surfaces dynamic-surfaces.json --observations runtime-observations.json [--json]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "[FAIL] missing jq" >&2; exit 2; }
[[ -f "$SURFACES" && -f "$OBSERVATIONS" ]] || { echo "[FAIL] missing surfaces or observations" >&2; exit 2; }
mkdir -p "$(dirname "$OUT")"

report=$(jq -n \
  --argjson surfaces "$(jq . "$SURFACES")" \
  --argjson runtime "$(jq . "$OBSERVATIONS")" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
  def key: (.kind + "\u0000" + .name);
  ($runtime.observations // []) as $obs
  | ($obs | map({key:(.kind + "\u0000" + .name), value:.}) | from_entries) as $obs_by_key
  | [
      $surfaces.nodes[]? as $n
      | ($obs_by_key[($n.kind + "\u0000" + $n.name)]) as $o
      | if $o then
          $n + {
            risk_level:"dynamic_observed",
            verification_status:"observed",
            observed:true,
            observation_hash:$o.hash,
            observation:$o,
            confidence:([1, (($n.confidence // 0) + 0.12)] | min)
          }
        else
          $n + {
            observed:false,
            verification_status:(if $n.risk_level=="dynamic_known" then "probe_gap" elif $n.risk_level=="dynamic_unsafe" then "unsafe" else "probe_gap" end)
          }
        end
    ] as $nodes
  | ($nodes | map(.kind + "\u0000" + .name)) as $known_keys
  | [
      $obs[]?
      | . as $runtime_node
      | select(($known_keys | index(($runtime_node.kind + "\u0000" + $runtime_node.name))) | not)
      | {
          id:(("observed_drift:" + $runtime_node.kind + ":" + $runtime_node.name) | gsub("[^A-Za-z0-9_.:-]"; "_")),
          kind:$runtime_node.kind,
          name:$runtime_node.name,
          path:($runtime_node.path // ""),
          line:0,
          module:"",
          component:"",
          resolver:"runtime_observation",
          confidence:0.98,
          risk_level:"dynamic_observed",
          verification_status:"observed",
          observed:true,
          semantic_links:[],
          evidence:{source:"runtime_probe", drift:"observed_but_not_static"},
          observation_hash:$runtime_node.hash,
          observation:$runtime_node,
          hash:$runtime_node.hash
        }
    ] as $drift
  | ($nodes + $drift | sort_by(.path,.line,.kind,.name)) as $all
  | {
      schema_version:"1.0",
      ok:true,
      generated_at:$generated_at,
      root:$surfaces.root,
      struct:$surfaces.struct,
      summary:{
        nodes:($all|length),
        observed:($all|map(select(.verification_status=="observed"))|length),
        observed_drift:($drift|length),
        probe_gaps:($all|map(select(.verification_status=="probe_gap"))|length),
        dynamic_known:($all|map(select(.risk_level=="dynamic_known"))|length),
        dynamic_observed:($all|map(select(.risk_level=="dynamic_observed"))|length),
        dynamic_unverified:($all|map(select(.risk_level=="dynamic_unverified"))|length),
        dynamic_unsafe:($all|map(select(.risk_level=="dynamic_unsafe"))|length)
      },
      nodes:$all,
      contract_hash:($all | map({id,hash,observation_hash:(.observation_hash // "")}) | tostring),
      drift:{observed_but_undocumented:$drift, static_inferred_but_unobserved:($all|map(select(.verification_status=="probe_gap")))}
    }')

printf '%s\n' "$report" > "$OUT"
[[ "$JSON_OUT" == "1" ]] && printf '%s\n' "$report" || jq -r '"Dynamic Observation Merge observed=" + (.summary.observed|tostring) + " probe_gaps=" + (.summary.probe_gaps|tostring) + " output='"$OUT"'"' <<<"$report"
