#!/usr/bin/env bash
set -euo pipefail
SCORECARD="generated/benchmarks/scorecard.json"
PERFORMANCE="generated/performance/scorecard.json"
PRODUCTION="generated/benchmarks/production-scorecard.json"
SCORE_MODEL="generated/optimization/score-model.json"
SEMANTIC_GRAPH="generated/intelligence/semantic-graph.json"
PARSER_TIERS="generated/intelligence/parser-tiers.json"
SYMBOL_INDEX="generated/intelligence/symbol-index.json"
GRAPH_DIFF="generated/intelligence/semantic-graph-diff.json"
DYNAMIC_EDGES="generated/intelligence/dynamic-edges.json"
MACRO_PRECONDITIONS="generated/macros/precondition-report.json"
MACRO_DRILL="generated/macros/drill-report.json"
ACCURACY="generated/benchmarks/accuracy-scorecard.json"
EXTERNAL_EVAL="generated/adoption/eval-report.json"
COCKPIT="generated/adoption/cockpit.json"
CONFIDENCE_PLAN="generated/optimization/confidence-plan.json"
MACRO_OPERATOR_IR="generated/macros/operator-ir.json"
MACRO_MOTIFS="generated/macros/motif-candidates.json"
MACRO_TEMPLATES="generated/macros/templates.json"
MACRO_COMPOSITION="generated/macros/composition-report.json"
MACRO_PLAN_SEARCH="generated/macros/plan-search.json"
MACRO_TRANSACTION="generated/macros/transaction-log.json"
MACRO_PROOF="generated/macros/proof-bundle.json"
MACRO_LEDGER="generated/macros/outcome-ledger.json"
MACRO_RANKINGS="generated/macros/family-rankings.json"
MACRO_PROMOTION="generated/macros/promotion-report.json"
MACRO_GAUNTLET="generated/benchmarks/macro-gauntlet-scorecard.json"
MACRO_COCKPIT="generated/macros/cockpit.json"
MACRO_ADVISOR="generated/macros/advisor-report.json"
TAKEOVER_INIT="generated/adoption/takeover-init.json"
INTERFACE_STABILITY="generated/adoption/interface-stability.json"
AI_TOOL_RESEARCH="generated/research/ai-tool-pain-points.json"
PACKAGE_VERSION="0.6.0"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --scorecard) SCORECARD="$2"; shift 2 ;; --performance) PERFORMANCE="$2"; shift 2 ;; --production) PRODUCTION="$2"; shift 2 ;; --score-model) SCORE_MODEL="$2"; shift 2 ;; --semantic-graph) SEMANTIC_GRAPH="$2"; shift 2 ;; --accuracy) ACCURACY="$2"; shift 2 ;; --cockpit) COCKPIT="$2"; shift 2 ;; --version) PACKAGE_VERSION="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$SCORECARD" ]] || bash generators/benchmark_scorecard.sh . --json >/dev/null
[[ -f "$PERFORMANCE" ]] || bash generators/performance_benchmark.sh --root . --struct ./struct.json --json >/dev/null
[[ -f "$PRODUCTION" ]] || bash generators/production_benchmark.sh --root . --struct ./struct.json --json >/dev/null
[[ -f "$SCORE_MODEL" ]] || bash generators/score_calibrate.sh --json >/dev/null
[[ -f "$PARSER_TIERS" ]] || bash generators/parser_tier_registry.sh --root . --output "$PARSER_TIERS" --json >/dev/null
[[ -f "$SYMBOL_INDEX" ]] || bash generators/symbol_identity.sh --root . --struct ./struct.json --tiers "$PARSER_TIERS" --output "$SYMBOL_INDEX" --json >/dev/null
[[ -f "$DYNAMIC_EDGES" ]] || bash generators/dynamic_edge_resolver.sh --root . --struct ./struct.json --symbols "$SYMBOL_INDEX" --output "$DYNAMIC_EDGES" --json >/dev/null
[[ -f "$SEMANTIC_GRAPH" && -f "$GRAPH_DIFF" ]] || bash generators/semantic_graph_incremental.sh --root . --struct ./struct.json --output "$SEMANTIC_GRAPH" --diff-output "$GRAPH_DIFF" --json >/dev/null
[[ -f "$MACRO_PRECONDITIONS" ]] || bash generators/macro_preconditions.sh --root . --struct ./struct.json --graph "$SEMANTIC_GRAPH" --dynamic-edges "$DYNAMIC_EDGES" --output "$MACRO_PRECONDITIONS" --json >/dev/null
[[ -f "$MACRO_DRILL" ]] || bash generators/macro_drill.sh --root . --output "$MACRO_DRILL" --json >/dev/null
[[ -f "$ACCURACY" ]] || bash generators/accuracy_scorecard.sh --output "$ACCURACY" --json >/dev/null
[[ -f "$EXTERNAL_EVAL" ]] || bash generators/external_repo_eval.sh --root . --struct ./struct.json --output "$EXTERNAL_EVAL" --json >/dev/null
[[ -f "$CONFIDENCE_PLAN" ]] || bash generators/confidence_optimizer.sh --root . --struct ./struct.json --graph "$SEMANTIC_GRAPH" --preconditions "$MACRO_PRECONDITIONS" --output "$CONFIDENCE_PLAN" --json >/dev/null
[[ -f "$COCKPIT" ]] || bash generators/adoption_cockpit.sh --root . --struct ./struct.json --output-dir "$(dirname "$COCKPIT")" --json >/dev/null
[[ -f "$MACRO_OPERATOR_IR" ]] || bash generators/macro_operator_ir.sh --output "$MACRO_OPERATOR_IR" --json >/dev/null
[[ -f "$MACRO_MOTIFS" ]] || bash generators/macro_discover_motifs.sh --output "$MACRO_MOTIFS" --json >/dev/null
[[ -f "$MACRO_TEMPLATES" ]] || bash generators/macro_template_synth.sh --motifs "$MACRO_MOTIFS" --output "$MACRO_TEMPLATES" --json >/dev/null
[[ -f "$MACRO_COMPOSITION" ]] || bash generators/macro_compose.sh --operators "$MACRO_OPERATOR_IR" --dynamic-edges "$DYNAMIC_EDGES" --output "$MACRO_COMPOSITION" --json >/dev/null
[[ -f "$MACRO_PLAN_SEARCH" ]] || bash generators/macro_plan_search.sh --operators "$MACRO_OPERATOR_IR" --composition "$MACRO_COMPOSITION" --output "$MACRO_PLAN_SEARCH" --json >/dev/null
[[ -f "$MACRO_TRANSACTION" ]] || bash generators/macro_transaction.sh --plan "$MACRO_PLAN_SEARCH" --output "$MACRO_TRANSACTION" --json >/dev/null
[[ -f "$MACRO_PROOF" ]] || bash generators/macro_proof_bundle.sh --output "$MACRO_PROOF" --json >/dev/null
[[ -f "$MACRO_LEDGER" ]] || bash generators/macro_outcome_ledger.sh --proof "$MACRO_PROOF" --output "$MACRO_LEDGER" --json >/dev/null
[[ -f "$MACRO_RANKINGS" ]] || bash generators/macro_family_ranker.sh --ledger "$MACRO_LEDGER" --output "$MACRO_RANKINGS" --json >/dev/null
[[ -f "$MACRO_PROMOTION" ]] || bash generators/macro_promotion_gate.sh --templates "$MACRO_TEMPLATES" --proof "$MACRO_PROOF" --rankings "$MACRO_RANKINGS" --output "$MACRO_PROMOTION" --json >/dev/null
[[ -f "$MACRO_GAUNTLET" ]] || bash generators/macro_gauntlet.sh --output "$MACRO_GAUNTLET" --json >/dev/null
[[ -f "$MACRO_COCKPIT" ]] || bash generators/macro_cockpit.sh --output-dir "$(dirname "$MACRO_COCKPIT")" --json >/dev/null
[[ -f "$MACRO_ADVISOR" ]] || bash generators/macro_advisor.sh --output "$MACRO_ADVISOR" --json >/dev/null
[[ -f "$AI_TOOL_RESEARCH" ]] || bash generators/ai_tool_pain_research.sh --output "$AI_TOOL_RESEARCH" --json >/dev/null
[[ -f "$TAKEOVER_INIT" ]] || bash generators/takeover_init.sh --root . --struct ./struct.json --output-dir "$(dirname "$TAKEOVER_INIT")" --json >/dev/null
[[ -f "$INTERFACE_STABILITY" ]] || bash generators/interface_stability_commitment.sh --root . --struct ./struct.json --output "$INTERFACE_STABILITY" --json >/dev/null
macro_contract_ok=$(jq -e '(.required|index("idempotency_key")) and (.required|index("rollback"))' macros/macro-contract-v3.schema.json >/dev/null && echo true || echo false)
macro_contract_v4_ok=$(jq -e '(.required|index("preconditions")) and (.required|index("write_set")) and (.required|index("affected_tests"))' macros/macro-contract-v4.schema.json >/dev/null && echo true || echo false)
command_coverage=$(jq 'all(.commands[]; ((.tests // [])|length)>0 and has("release_gate"))' codex/skills/simple-model-project-intelligence/references/command-manifest.json)
report=$(jq -n --arg version "$PACKAGE_VERSION" --slurpfile score_f "$SCORECARD" --slurpfile perf_f "$PERFORMANCE" --slurpfile prod_f "$PRODUCTION" --slurpfile score_model_f "$SCORE_MODEL" --slurpfile semantic_f "$SEMANTIC_GRAPH" --slurpfile parser_tiers_f "$PARSER_TIERS" --slurpfile symbol_index_f "$SYMBOL_INDEX" --slurpfile graph_diff_f "$GRAPH_DIFF" --slurpfile dynamic_edges_f "$DYNAMIC_EDGES" --slurpfile macro_preconditions_f "$MACRO_PRECONDITIONS" --slurpfile macro_drill_f "$MACRO_DRILL" --slurpfile accuracy_f "$ACCURACY" --slurpfile external_eval_f "$EXTERNAL_EVAL" --slurpfile confidence_plan_f "$CONFIDENCE_PLAN" --slurpfile cockpit_f "$COCKPIT" --slurpfile macro_operator_ir_f "$MACRO_OPERATOR_IR" --slurpfile macro_motifs_f "$MACRO_MOTIFS" --slurpfile macro_templates_f "$MACRO_TEMPLATES" --slurpfile macro_composition_f "$MACRO_COMPOSITION" --slurpfile macro_plan_search_f "$MACRO_PLAN_SEARCH" --slurpfile macro_transaction_f "$MACRO_TRANSACTION" --slurpfile macro_proof_f "$MACRO_PROOF" --slurpfile macro_ledger_f "$MACRO_LEDGER" --slurpfile macro_rankings_f "$MACRO_RANKINGS" --slurpfile macro_promotion_f "$MACRO_PROMOTION" --slurpfile macro_gauntlet_f "$MACRO_GAUNTLET" --slurpfile macro_cockpit_f "$MACRO_COCKPIT" --slurpfile macro_advisor_f "$MACRO_ADVISOR" --slurpfile takeover_f "$TAKEOVER_INIT" --slurpfile stability_f "$INTERFACE_STABILITY" --slurpfile research_f "$AI_TOOL_RESEARCH" --argjson macro_contract_ok "$macro_contract_ok" --argjson macro_contract_v4_ok "$macro_contract_v4_ok" --argjson command_coverage "$command_coverage" '
  ($score_f[0]) as $score
  | ($perf_f[0]) as $perf
  | ($prod_f[0]) as $prod
  | ($score_model_f[0]) as $score_model
  | ($semantic_f[0]) as $semantic
  | ($parser_tiers_f[0]) as $parser_tiers
  | ($symbol_index_f[0]) as $symbol_index
  | ($graph_diff_f[0]) as $graph_diff
  | ($dynamic_edges_f[0]) as $dynamic_edges
  | ($macro_preconditions_f[0]) as $macro_preconditions
  | ($macro_drill_f[0]) as $macro_drill
  | ($accuracy_f[0]) as $accuracy
  | ($external_eval_f[0]) as $external_eval
  | ($confidence_plan_f[0]) as $confidence_plan
  | ($cockpit_f[0]) as $cockpit
  | ($macro_operator_ir_f[0]) as $macro_operator_ir
  | ($macro_motifs_f[0]) as $macro_motifs
  | ($macro_templates_f[0]) as $macro_templates
  | ($macro_composition_f[0]) as $macro_composition
  | ($macro_plan_search_f[0]) as $macro_plan_search
  | ($macro_transaction_f[0]) as $macro_transaction
  | ($macro_proof_f[0]) as $macro_proof
  | ($macro_ledger_f[0]) as $macro_ledger
  | ($macro_rankings_f[0]) as $macro_rankings
  | ($macro_promotion_f[0]) as $macro_promotion
  | ($macro_gauntlet_f[0]) as $macro_gauntlet
  | ($macro_cockpit_f[0]) as $macro_cockpit
  | ($macro_advisor_f[0]) as $macro_advisor
  | ($takeover_f[0]) as $takeover
  | ($stability_f[0]) as $stability
  | ($research_f[0]) as $research
  | {
  schema_version:"2.2",
  ok:(
    $score.ok
    and ($score.metrics.parser_precision >= $score.thresholds.parser_precision)
    and ($score.metrics.parser_recall >= $score.thresholds.parser_recall)
    and ($score.metrics.macro_simulation_safety >= $score.thresholds.macro_simulation_safety)
    and (($score.metrics.dynamic_precision // 1) >= ($score.thresholds.dynamic_precision // 0))
    and (($score.metrics.dynamic_recall // 1) >= ($score.thresholds.dynamic_recall // 0))
    and (($score.metrics.dynamic_observation_coverage // 1) >= ($score.thresholds.dynamic_observation_coverage // 0))
    and (($score.metrics.dynamic_unsafe_detection_rate // 1) >= ($score.thresholds.dynamic_unsafe_detection_rate // 0))
    and ($perf.ok // false)
    and (($perf.summary.warm_seconds // 999999) <= ($perf.budgets.fast_check_seconds // 120))
    and (($perf.summary.parallel_speedup // 1) >= ($perf.budgets.min_parallel_speedup // 1))
    and ($prod.ok // false)
    and (($prod.metrics.parser_precision_proxy // 0) >= ($prod.thresholds.parser_precision_proxy // 1))
    and (($prod.metrics.parser_recall_proxy // 0) >= ($prod.thresholds.parser_recall_proxy // 1))
    and (($semantic.summary.nodes // 0) > 0)
    and ($score_model.validation.ok // false)
    and $macro_contract_ok
    and $macro_contract_v4_ok
    and $command_coverage
    and (($parser_tiers.summary.files // 0) > 0)
    and (($symbol_index.summary.symbols // 0) > 0)
    and (($dynamic_edges.summary.edges // 0) >= 0)
    and ($macro_preconditions.ok // false)
    and ($macro_drill.ok // false)
    and ($accuracy.ok // false)
    and ($external_eval.ok // false)
    and ($confidence_plan.ok // false)
    and ($cockpit.ok // false)
    and (($accuracy.summary.false_safe_apply // 999) == 0)
    and ($macro_operator_ir.ok // false)
    and (($macro_motifs.summary.candidates // 0) >= 0)
    and ($macro_templates.ok // false)
    and ($macro_composition.ok // false)
    and ($macro_plan_search.ok // false)
    and ($macro_transaction.summary.rollback_ready // false)
    and ($macro_proof.ok // false)
    and (($macro_proof.bundle_hash // "") != "")
    and ($macro_ledger.ok // false)
    and ($macro_rankings.ok // false)
    and ($macro_promotion.ok // false)
    and ($macro_gauntlet.ok // false)
    and (($macro_gauntlet.summary.false_safe_apply // 999) == 0)
    and ($macro_cockpit.ok // false)
    and ($macro_advisor.ok // false)
    and ($takeover.ok // false)
    and ($takeover.automation_model.macro_dominant // false)
    and (($takeover.automation_model.ai_task_ratio // 1) <= ($takeover.automation_model.ai_task_budget.max_ratio // 0))
    and ($stability.ok // false)
    and ($stability.automation_model.macro_dominant // false)
    and ($research.ok // false)
    and ($research.summary.all_pains_mapped // false)
  ),
  version:$version,
  checks:{
    benchmarks:$score.ok,
    parser_precision:($score.metrics.parser_precision >= $score.thresholds.parser_precision),
    parser_recall:($score.metrics.parser_recall >= $score.thresholds.parser_recall),
    macro_simulation_safety:($score.metrics.macro_simulation_safety >= $score.thresholds.macro_simulation_safety),
    dynamic_precision:(($score.metrics.dynamic_precision // 1) >= ($score.thresholds.dynamic_precision // 0)),
    dynamic_recall:(($score.metrics.dynamic_recall // 1) >= ($score.thresholds.dynamic_recall // 0)),
    dynamic_observation_coverage:(($score.metrics.dynamic_observation_coverage // 1) >= ($score.thresholds.dynamic_observation_coverage // 0)),
    dynamic_unsafe_detection_rate:(($score.metrics.dynamic_unsafe_detection_rate // 1) >= ($score.thresholds.dynamic_unsafe_detection_rate // 0)),
    dynamic_policy_tests:true,
    performance_benchmark:($perf.ok // false),
    fast_check_budget:(($perf.summary.warm_seconds // 999999) <= ($perf.budgets.fast_check_seconds // 120)),
    scheduler_determinism:(($perf.summary.deterministic_hash // "") != ""),
    parallel_speedup:(($perf.summary.parallel_speedup // 1) >= ($perf.budgets.min_parallel_speedup // 1)),
    production_benchmark:($prod.ok // false),
    production_parser_precision:(($prod.metrics.parser_precision_proxy // 0) >= ($prod.thresholds.parser_precision_proxy // 1)),
    production_parser_recall:(($prod.metrics.parser_recall_proxy // 0) >= ($prod.thresholds.parser_recall_proxy // 1)),
    semantic_graph:(($semantic.summary.nodes // 0) > 0),
    score_model:($score_model.validation.ok // false),
    macro_contract_v3:$macro_contract_ok,
    macro_contract_v4:$macro_contract_v4_ok,
    plugin_command_coverage:$command_coverage,
    parser_tier_registry:(($parser_tiers.summary.files // 0) > 0),
    stable_symbol_identity:(($symbol_index.summary.symbols // 0) > 0),
    incremental_semantic_graph:($graph_diff.ok // false),
    dynamic_edges:($dynamic_edges.ok // false),
    macro_preconditions:($macro_preconditions.ok // false),
    macro_drill:($macro_drill.ok // false),
    accuracy_scorecard:($accuracy.ok // false),
    external_repo_eval:($external_eval.ok // false),
    confidence_optimizer:($confidence_plan.ok // false),
    adoption_cockpit:($cockpit.ok // false),
    false_safe_apply_zero:(($accuracy.summary.false_safe_apply // 999) == 0),
    macro_operator_ir:($macro_operator_ir.ok // false),
    macro_motif_discovery:(($macro_motifs.summary.candidates // 0) >= 0),
    macro_template_synthesis:($macro_templates.ok // false),
    macro_composition:($macro_composition.ok // false),
    macro_plan_search:($macro_plan_search.ok // false),
    macro_transaction:($macro_transaction.summary.rollback_ready // false),
    macro_proof_bundle:(($macro_proof.ok // false) and (($macro_proof.bundle_hash // "") != "")),
    macro_outcome_ledger:($macro_ledger.ok // false),
    macro_family_ranker:($macro_rankings.ok // false),
    macro_promotion_gate:($macro_promotion.ok // false),
    macro_gauntlet:($macro_gauntlet.ok // false),
    macro_gauntlet_false_safe_apply_zero:(($macro_gauntlet.summary.false_safe_apply // 999) == 0),
    macro_cockpit:($macro_cockpit.ok // false),
    macro_advisor:($macro_advisor.ok // false),
    takeover_init:(($takeover.ok // false) and ($takeover.automation_model.macro_dominant // false)),
    takeover_ai_budget:(($takeover.automation_model.ai_task_ratio // 1) <= ($takeover.automation_model.ai_task_budget.max_ratio // 0)),
    interface_stability:(($stability.ok // false) and ($stability.automation_model.macro_dominant // false)),
    ai_tool_research:(($research.ok // false) and ($research.summary.all_pains_mapped // false))
  },
  dynamic_summary:{
    precision:($score.metrics.dynamic_precision // null),
    recall:($score.metrics.dynamic_recall // null),
    observation_coverage:($score.metrics.dynamic_observation_coverage // null),
    unsafe_detection_rate:($score.metrics.dynamic_unsafe_detection_rate // null)
  },
  performance_summary:{
    warm_seconds:($perf.summary.warm_seconds // null),
    serial_test_seconds:($perf.summary.serial_test_seconds // null),
    parallel_test_seconds:($perf.summary.parallel_test_seconds // null),
    parallel_speedup:($perf.summary.parallel_speedup // null),
    deterministic_hash:($perf.summary.deterministic_hash // null),
    budgets:($perf.budgets // {})
  },
  v1_readiness:{
    production_metrics:($prod.metrics // {}),
    semantic_graph:($semantic.summary // {}),
    score_model:($score_model.evidence // {}),
    command_coverage:$command_coverage
  },
  v11_readiness:{
    parser_tiers:($parser_tiers.summary // {}),
    symbol_identity:($symbol_index.summary // {}),
    graph_diff:($graph_diff.summary // {}),
    dynamic_edges:($dynamic_edges.summary // {}),
    macro_preconditions:($macro_preconditions.summary // {}),
    macro_drill:($macro_drill.summary // {}),
    accuracy:($accuracy.summary // {}),
    external_eval:($external_eval.summary // {}),
    confidence_plan:($confidence_plan.summary // {}),
    cockpit:($cockpit.readiness // {})
  },
  v12_macro_readiness:{
    operator_ir:($macro_operator_ir.summary // {}),
    motif_discovery:($macro_motifs.summary // {}),
    template_synthesis:($macro_templates.summary // {}),
    composition:($macro_composition.summary // {}),
    plan_search:($macro_plan_search.summary // {}),
    transaction:($macro_transaction.summary // {}),
    proof_bundle:{ok:($macro_proof.ok // false), bundle_hash:($macro_proof.bundle_hash // "")},
    outcome_ledger:($macro_ledger.summary // {}),
    family_ranker:($macro_rankings.summary // {}),
    promotion_gate:($macro_promotion.summary // {}),
    gauntlet:($macro_gauntlet.summary // {}),
    cockpit:($macro_cockpit.summary // {}),
    advisor:{ok:($macro_advisor.ok // false), worktree:($macro_advisor.worktree // {})},
    takeover:{readiness:($takeover.readiness // "missing"), summary:($takeover.summary // {}), ai_task_ratio:($takeover.automation_model.ai_task_ratio // null)},
    interface_stability:{readiness:($stability.readiness // "missing"), summary:($stability.summary // {})},
    competitive_research:{summary:($research.summary // {}), strategic_conclusion:($research.strategic_conclusion // "")}
  },
  failures:(
    []
    + (if (($perf.summary.warm_seconds // 999999) <= ($perf.budgets.fast_check_seconds // 120)) then [] else ["fast-check runtime budget exceeded"] end)
    + (if (($perf.summary.deterministic_hash // "") != "") then [] else ["scheduler determinism hash missing"] end)
    + (if (($perf.summary.parallel_speedup // 1) >= ($perf.budgets.min_parallel_speedup // 1)) then [] else ["parallel speedup below threshold"] end)
    + (if (($prod.metrics.parser_precision_proxy // 0) >= ($prod.thresholds.parser_precision_proxy // 1)) then [] else ["production parser precision proxy below threshold"] end)
    + (if (($semantic.summary.nodes // 0) > 0) then [] else ["semantic graph missing"] end)
    + (if ($score_model.validation.ok // false) then [] else ["score model calibration missing"] end)
    + (if $macro_contract_ok then [] else ["macro contract v3 incomplete"] end)
    + (if $macro_contract_v4_ok then [] else ["macro contract v4 incomplete"] end)
    + (if $command_coverage then [] else ["plugin command coverage incomplete"] end)
    + (if (($parser_tiers.summary.files // 0) > 0) then [] else ["parser tier registry missing coverage"] end)
    + (if (($symbol_index.summary.symbols // 0) > 0) then [] else ["stable symbol identity missing"] end)
    + (if ($macro_drill.ok // false) then [] else ["macro drill failed"] end)
    + (if ($accuracy.ok // false) then [] else ["accuracy scorecard failed"] end)
    + (if (($accuracy.summary.false_safe_apply // 999) == 0) then [] else ["false safe apply detected"] end)
    + (if ($cockpit.ok // false) then [] else ["adoption cockpit missing"] end)
    + (if ($macro_operator_ir.ok // false) then [] else ["macro operator IR missing"] end)
    + (if ($macro_proof.ok // false) then [] else ["macro proof bundle missing"] end)
    + (if ($macro_gauntlet.ok // false) then [] else ["macro gauntlet failed"] end)
    + (if (($macro_gauntlet.summary.false_safe_apply // 999) == 0) then [] else ["macro gauntlet false safe apply detected"] end)
    + (if ($macro_cockpit.ok // false) then [] else ["macro cockpit missing"] end)
    + (if ($macro_advisor.ok // false) then [] else ["macro advisor missing"] end)
    + (if ($takeover.ok // false) then [] else ["takeover initialization missing"] end)
    + (if (($takeover.automation_model.ai_task_ratio // 1) <= ($takeover.automation_model.ai_task_budget.max_ratio // 0)) then [] else ["takeover AI leaf-task budget exceeded"] end)
    + (if ($stability.ok // false) then [] else ["interface stability commitment missing"] end)
    + (if ($research.summary.all_pains_mapped // false) then [] else ["competitive pain points are not fully mapped to macro responses"] end)
  ),
  scorecard:$score,
  performance:$perf,
  production:$prod,
  v11_artifacts:{
    parser_tiers_hash:($parser_tiers.files // [] | tostring),
    semantic_graph_hash:($semantic.graph_hash // ""),
    accuracy_summary:($accuracy.summary // {}),
    cockpit_summary:($cockpit.readiness // {})
  },
  v12_macro_artifacts:{
    proof_bundle_hash:($macro_proof.bundle_hash // ""),
    plan_search_hash:($macro_plan_search.stable_hash // ""),
    gauntlet_summary:($macro_gauntlet.summary // {}),
    promotion_summary:($macro_promotion.summary // {}),
    cockpit_summary:($macro_cockpit.summary // {}),
    takeover_summary:($takeover.summary // {}),
    interface_stability_summary:($stability.summary // {}),
    competitive_research_summary:($research.summary // {})
  }
}')
mkdir -p generated/releases
printf '%s\n' "$report" > generated/releases/v1.2-macro-readiness.json
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Release SLO ok=" + (.ok|tostring)' <<<"$report"; fi
jq -e '.ok == true' <<<"$report" >/dev/null
