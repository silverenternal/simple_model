#!/usr/bin/env bash
set -euo pipefail
POLICY=""
PLAN=""
SIMULATION=""
DYNAMIC=""
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --policy) POLICY="$2"; shift 2 ;;
    --plan) PLAN="$2"; shift 2 ;;
    --simulation) SIMULATION="$2"; shift 2 ;;
    --dynamic) DYNAMIC="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
policy_json='{"schema_version":"1.0","macro":{"max_risk":"medium","allowed_tiers":["advisory","exec_readonly","struct_only","safe_codemod"],"require_simulation":true,"require_clean_worktree":false},"release":{"allow_breaking_contracts":false,"require_benchmark_scorecard":false}}'
[[ -n "$POLICY" && -f "$POLICY" ]] && policy_json=$(jq . "$POLICY")
plan_json='{"actions":[]}'
[[ -n "$PLAN" && -f "$PLAN" ]] && plan_json=$(jq . "$PLAN")
simulation_json='null'
[[ -n "$SIMULATION" && -f "$SIMULATION" ]] && simulation_json=$(jq . "$SIMULATION")
dynamic_json='{"nodes":[],"summary":{"nodes":0}}'
[[ -n "$DYNAMIC" && -f "$DYNAMIC" ]] && dynamic_json=$(jq . "$DYNAMIC")
report=$(jq -n --argjson policy "$policy_json" --argjson plan "$plan_json" --argjson simulation "$simulation_json" --argjson dynamic "$dynamic_json" '
  def rank($r): {"low":1,"medium":2,"high":3,"critical":4}[$r] // 4;
  def action_paths($a): (($a.writes // []) + [($a.target.path // empty)] + [($a.target.struct // empty)] | map(select(. != null and . != "")));
  def touches($a; $n):
    (action_paths($a)) as $paths
    | (($a.dynamic_surface_ids // []) | index($n.id)) != null
      or ($paths | any(. as $p | ($n.path == $p or ($p|endswith($n.path)) or ($n.path|endswith($p)))))
      or (($a.target.component // "") != "" and ($a.target.component // "") == ($n.component // ""));
  def waiver_ok($a; $n):
    (($a.waivers // []) | any((.surface_id // "") == $n.id and (.expires // "9999-12-31") >= "2026-07-09"));
  ($policy.macro.max_risk // "medium") as $max
  | ($policy.macro.allowed_tiers // ["advisory","exec_readonly","struct_only","safe_codemod"]) as $tiers
  | ($simulation != null and ($simulation.ok // false) == true) as $sim_ok
  | ($dynamic.nodes // []) as $dnodes
  | [
      ($plan.actions // [])[] as $a
      | []
        + (if rank($a.risk // "critical") > rank($max) then [{id:$a.id, macro_id:$a.macro_id, risk:$a.risk, tier:($a.execution_tier // "unknown"), reason:"macro risk exceeds policy max"}] else [] end)
        + (if (($tiers | index($a.execution_tier // "unknown")) == null) then [{id:$a.id, macro_id:$a.macro_id, risk:$a.risk, tier:($a.execution_tier // "unknown"), reason:"execution tier is not allowed by policy"}] else [] end)
        + (if (($a.policy.simulation_required // false) and ($policy.macro.require_simulation // true) and ($sim_ok|not)) then [{id:$a.id, macro_id:$a.macro_id, risk:$a.risk, tier:($a.execution_tier // "unknown"), reason:"simulation is required and missing or failed"}] else [] end)
        + [
            $dnodes[]?
            | select(touches($a; .))
            | select((.risk_level == "dynamic_unsafe" or .verification_status != "observed") and (waiver_ok($a; .)|not))
            | {
                id:$a.id,
                macro_id:$a.macro_id,
                risk:$a.risk,
                tier:($a.execution_tier // "unknown"),
                surface_id:.id,
                surface_kind:.kind,
                surface_risk:.risk_level,
                verification_status:.verification_status,
                reason:(if .risk_level == "dynamic_unsafe" then "dynamic unsafe surface requires explicit waiver" else "dynamic surface requires runtime observation before apply" end)
              }
          ]
    ] | flatten as $denied
  | [
      ($plan.actions // [])[] as $a
      | $dnodes[]?
      | select(touches($a; .))
      | {id:$a.id, macro_id:$a.macro_id, surface_id:.id, surface_kind:.kind, verification_status:.verification_status, message:"dynamic surface participates in this action"}
    ] as $dynamic_hits
  | {
      schema_version:"2.0",
      ok:($denied|length == 0),
      decision:(if ($denied|length)==0 then "allow" else "deny" end),
      policy:$policy,
      summary:{actions:(($plan.actions // [])|length), denied:($denied|length), warnings:($dynamic_hits|length), simulation_ok:$sim_ok, dynamic_surfaces:($dnodes|length), dynamic_hits:($dynamic_hits|length)},
      deny:$denied,
      warn:$dynamic_hits,
      required_actions:(
        []
        + (if (($policy.macro.require_simulation // true) and (($plan.actions // [])|map(select(.policy.simulation_required == true))|length) > 0 and ($sim_ok|not)) then ["run macro_simulate before apply"] else [] end)
        + (if ($denied|map(select(.verification_status and .verification_status != "observed"))|length) > 0 then ["run runtime_probe and dynamic_observation_merge for affected dynamic surfaces"] else [] end)
        + (if ($denied|map(select(.surface_risk == "dynamic_unsafe"))|length) > 0 then ["add explicit expiring waiver or avoid automated apply for dynamic_unsafe surfaces"] else [] end)
      ),
      dynamic:{summary:($dynamic.summary // {nodes:0}), affected:$dynamic_hits},
      evidence:{plan_schema:($plan.schema_version // "unknown"), simulation_schema:($simulation.schema_version // "none"), dynamic_schema:($dynamic.schema_version // "none")}
    }')
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Policy decision=" + .decision + " denied=" + (.summary.denied|tostring)' <<<"$report"; fi
jq -e '.ok == true' <<<"$report" >/dev/null
