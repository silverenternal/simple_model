#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
OUT_DIR="generated/adoption"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --output-dir|-o) OUT_DIR="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
STRUCT="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"
[[ -f "$STRUCT" ]] || { echo "[FAIL] missing struct: $STRUCT" >&2; exit 2; }
mkdir -p "$OUT_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bash "$SELF_DIR/external_repo_eval.sh" --root "$ROOT" --struct "$STRUCT" --output "$tmp/eval.json" --json >/dev/null
bash "$SELF_DIR/parser_tier_registry.sh" --root "$ROOT" --output "$tmp/tiers.json" --json >/dev/null
bash "$SELF_DIR/semantic_graph_incremental.sh" --root "$ROOT" --struct "$STRUCT" --output "$tmp/graph.json" --diff-output "$tmp/graph-diff.json" --json >/dev/null
bash "$SELF_DIR/dynamic_edge_resolver.sh" --root "$ROOT" --struct "$STRUCT" --output "$tmp/dynamic.json" --json >/dev/null
bash "$SELF_DIR/macro_discover_motifs.sh" --root "$ROOT" --struct "$STRUCT" --graph "$tmp/graph.json" --dynamic-edges "$tmp/dynamic.json" --parser-tiers "$tmp/tiers.json" --output "$tmp/motifs.json" --json >/dev/null
jq '.artifacts.affected_tests // {ok:false,summary:{tests:0},tests:[]}' "$tmp/eval.json" > "$tmp/tests.json"
bash "$SELF_DIR/interface_stability_commitment.sh" --root "$ROOT" --struct "$STRUCT" --graph "$tmp/graph.json" --graph-diff "$tmp/graph-diff.json" --dynamic-edges "$tmp/dynamic.json" --tests "$tmp/tests.json" --output "$OUT_DIR/interface-stability.json" --markdown "$OUT_DIR/interface-stability.md" --json >/dev/null

report=$(jq -n \
  --arg root "$ROOT" --arg struct "$STRUCT" --arg out_dir "$OUT_DIR" \
  --slurpfile eval "$tmp/eval.json" --slurpfile tiers "$tmp/tiers.json" --slurpfile graph "$tmp/graph.json" \
  --slurpfile graph_diff "$tmp/graph-diff.json" --slurpfile dyn "$tmp/dynamic.json" --slurpfile motifs "$tmp/motifs.json" \
  --slurpfile stability "$OUT_DIR/interface-stability.json" '
  def command($id;$cmd;$artifact;$blocking): {id:$id, owner:"macro", command:$cmd, artifact:$artifact, blocking:$blocking, deterministic:true};
  ([
    command("environment-doctor";"simple_model_pi.sh doctor --json";"doctor report";true),
    command("resolve-struct";"./bootstrap.sh --resolve --json";"generated/.bootstrap/resolved.struct.json";true),
    command("repository-audit";"./bootstrap.sh --adoption-audit <repo> --json";"adoption audit";false),
    command("parser-tiering";"simple_model_pi.sh parser-tiers --json";"generated/intelligence/parser-tiers.json";true),
    command("semantic-index";"simple_model_pi.sh semantic-graph-incremental --json";"generated/intelligence/semantic-graph.json";true),
    command("dynamic-governance";"simple_model_pi.sh dynamic-edges --json";"generated/intelligence/dynamic-edges.json";true),
    command("interface-commitment";"simple_model_pi.sh interface-stability --json";"generated/adoption/interface-stability.json";true),
    command("motif-discovery";"simple_model_pi.sh macro-motifs --json";"generated/macros/motif-candidates.json";false),
    command("macro-safety";"simple_model_pi.sh macro-preconditions --json";"generated/macros/precondition-report.json";true),
    command("validation";"simple_model_pi.sh affected-check --json";"generated/tests/affected-run.json";true)
  ] | to_entries | map(.value + {order:(.key+1), phase:(if .key<2 then "bootstrap" elif .key<6 then "evidence" elif .key<9 then "governance" else "gate" end)})) as $phases
  | ([
      ($stability[0].interfaces[]? | select(.status=="blocked") | {id:("blocked-interface:"+.id), severity:"blocking", evidence:.required_evidence, remediation:.macro_recommendations}),
      ($dyn[0].edges[]? | select(.blocks_safe_apply==true) | {id:("dynamic-edge:"+.id), severity:"blocking", evidence:[.trust_state,.path], remediation:["gather runtime observation or trusted structural evidence"]}),
      ($tiers[0].files[]? | select((.confidence // 1)<0.8) | {id:("parser-tier:"+.path), severity:"review", evidence:[.backend // "unknown",(.confidence|tostring)], remediation:["install or configure a structural parser backend"]})
    ] | unique_by(.id)) as $blockers
  | ([ $motifs[0].candidates[]? | select(.action=="review-first") | {id, family, action, confidence, graph_path} ] | .[:20]) as $review_actions
  | ([ $stability[0].interfaces[]?.macro_recommendations[]?, ($motifs[0].candidates[]? | select(.action=="gather-evidence") | (.family+":"+.motif)) ] | unique | map({macro:., mode:"simulate-first", structural_decision_owner:"macro"}) | .[:30]) as $macro_actions
  | (($stability[0].ai_leaf_tasks // []) + [
      {id:"ai-leaf:domain-glossary",task:"confirm ambiguous domain terms found during takeover",inputs:["struct component names","unresolved symbol names"],output_schema:{term:"string",definition:"string",owner:"string"},may_change_structure:false,requires_human_approval:true}
    ] | unique_by(.id) | .[:8]) as $ai_tasks
  | {
      schema_version:"1.0", ok:true, root:$root, struct:$struct,
      readiness:(if ($stability[0].summary.interfaces // 0)==0 then "evidence-incomplete" elif any($blockers[]?; .severity=="blocking") then "blocked-for-apply" else "ready-for-simulated-optimization" end),
      summary:{phases:($phases|length), blockers:($blockers|length), macro_safe_actions:($macro_actions|length), review_actions:($review_actions|length), ai_leaf_tasks:($ai_tasks|length), graph_nodes:($graph[0].summary.nodes // 0), graph_edges:($graph[0].summary.edges // 0)},
      phases:$phases, blockers:$blockers, macro_safe_actions:$macro_actions, review_actions:$review_actions,
      evidence_gaps:([$blockers[]? | {id,severity,evidence}] | unique_by(.id)), ai_leaf_tasks:$ai_tasks,
      interface_stability:{readiness:$stability[0].readiness,summary:$stability[0].summary,artifact:($out_dir+"/interface-stability.json")},
      evidence:{external_eval:$eval[0].summary, parser_tiers:$tiers[0].summary, semantic_graph:$graph[0].summary, graph_diff:$graph_diff[0], dynamic_edges:$dyn[0].summary, motifs:$motifs[0].summary},
      next_commands:($phases | map(.command)),
      automation_model:{macro_dominant:true, structural_decisions_by:"deterministic phases and policy gates", ai_role:"bounded clarification with typed input/output", ai_task_budget:{max_count:8,max_ratio:0.10}, ai_task_ratio:(if (($phases|length)+($blockers|length)+($macro_actions|length)+($review_actions|length)+($ai_tasks|length))==0 then 0 else (($ai_tasks|length) / (($phases|length)+($blockers|length)+($macro_actions|length)+($review_actions|length)+($ai_tasks|length))) end), ai_may_apply_changes:false},
      safety:{read_only:true, target_mutations:false, network_required:false, apply_requires_clean_worktree_and_passing_gates:true}
    }')

printf '%s\n' "$report" > "$OUT_DIR/takeover-init.json"
jq -r '
  "# Half-built Project Takeover", "",
  "- readiness: " + .readiness,
  "- deterministic phases: " + (.summary.phases|tostring),
  "- blockers: " + (.summary.blockers|tostring),
  "- macro actions: " + (.summary.macro_safe_actions|tostring),
  "- AI leaf tasks: " + (.summary.ai_leaf_tasks|tostring), "",
  "## Ordered Initialization", "",
  (.phases[] | (.order|tostring) + ". `" + .command + "` -> `" + .artifact + "`"), "",
  "## Blockers", "", (.blockers[]? | "- " + .id + ": " + (.evidence|join("; "))), "",
  "## Macro-safe Actions", "", (.macro_safe_actions[]? | "- " + .macro + " (" + .mode + ")"), "",
  "## AI Leaf Clarifications", "", (.ai_leaf_tasks[]? | "- " + .id + ": " + .task)
' "$OUT_DIR/takeover-init.json" > "$OUT_DIR/takeover-init.md"

if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Takeover readiness=" + .readiness + " phases=" + (.summary.phases|tostring) + " blockers=" + (.summary.blockers|tostring)' <<<"$report"; fi
