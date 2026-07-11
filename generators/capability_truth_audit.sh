#!/usr/bin/env bash
set -euo pipefail

ROOT="."
STRUCT="struct.json"
SPEC="specs/capability-maturity.json"
OUT="generated/audits/capability-truth.json"
FIXTURES="benchmarks/messy-repo-corpus/ts-python-go-monorepo"
JSON_OUT=0

usage() {
    cat <<'USAGE'
Usage:
  generators/capability_truth_audit.sh \
    [--root PATH] [--struct PATH] [--spec PATH] [--output PATH] [--fixtures LIST] [--json]

--fixtures is a comma-separated list of repository roots.

The script audits command-chain evidence end-to-end and classifies production-readiness
capability by command output artifacts, rollback/replay determinism, and fixture generalization.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --root) ROOT="$2"; shift 2 ;;
        --struct) STRUCT="$2"; shift 2 ;;
        --spec) SPEC="$2"; shift 2 ;;
        --output) OUT="$2"; shift 2 ;;
        --fixtures) FIXTURES="$2"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 64 ;;
    esac
done

ROOT="$(cd "$ROOT" && pwd)"
if [[ "$STRUCT" = /* ]]; then
    [[ -f "$STRUCT" ]] || { echo "[FAIL] struct not found: $STRUCT" >&2; exit 2; }
else
    if [[ -f "$ROOT/$STRUCT" ]]; then
        STRUCT="$ROOT/$STRUCT"
    elif [[ -f "$PWD/$STRUCT" ]]; then
        STRUCT="$PWD/$STRUCT"
    else
        echo "[FAIL] struct not found: $STRUCT" >&2
        exit 2
    fi
fi

mkdir -p "$(dirname "$OUT")"

WORKSPACE="$(mktemp -d)/workspace"
ARTIFACT_REL="generated/audits/capability-truth/latest"
ARTIFACT_DIR="$ROOT/$ARTIFACT_REL"
mkdir -p "$WORKSPACE" "$ARTIFACT_DIR"

copy_workspace() {
    local source="$1"
    local target="$2"
    mkdir -p "$target"
    if command -v rsync >/dev/null 2>&1; then
        rsync -a \
          --exclude '.git/' \
          --exclude 'node_modules/' \
          --exclude 'target/' \
          --exclude 'dist/' \
          --exclude 'build/' \
          --exclude '.venv/' \
          --exclude '__pycache__/' \
          "$source/" "$target/"
    else
        (cd "$source" && find . \
          -path './.git' -prune -o \
          -path './node_modules' -prune -o \
          -path './target' -prune -o \
          -path './dist' -prune -o \
          -path './build' -prune -o \
          -path './.venv' -prune -o \
          -path './__pycache__' -prune -o \
          \( -type f -o -type l \) -print) | while IFS= read -r rel; do
            mkdir -p "$target/$(dirname "$rel")"
            cp -a "$source/$rel" "$target/$rel"
        done
    fi
}

map_to_workspace_path() {
    local p="$1"
    if [[ "$p" == "$ROOT/"* ]]; then
        echo "$WORKSPACE${p#"$ROOT"}"
    elif [[ "$p" == "$ROOT" ]]; then
        echo "$WORKSPACE"
    else
        echo "$p"
    fi
}

file_hash() {
    local path="$1"
    if [[ -f "$path" ]]; then
        if command -v sha256sum >/dev/null 2>&1; then
            sha256sum "$path" | awk '{print $1}'
        else
            shasum -a 256 "$path" | awk '{print $1}'
        fi
    else
        echo ""
    fi
}

run_cmd() {
    local out_file="$1"
    shift
    local rc=0
    set +e
    "$@" > "$out_file" 2>&1
    rc=$?
    set -e
    echo "$rc"
}

bool_json() {
    local file="$1"
    local expr="$2"
    if [[ -f "$file" ]]; then
        jq -e "$expr" "$file" >/dev/null 2>&1 && echo true || echo false
    else
        echo false
    fi
}

int_json() {
    local file="$1"
    local expr="$2"
    local default="${3:-0}"
    if [[ -f "$file" ]]; then
        jq -r "$expr // $default" "$file" 2>/dev/null || echo "$default"
    else
        echo "$default"
    fi
}

load_threshold() {
    local path="$1"
    local default="$2"
    if [[ -f "$SPEC" ]] && jq -e "$path" "$SPEC" >/dev/null 2>&1; then
        jq -r "$path" "$SPEC"
    else
        echo "$default"
    fi
}

persist_artifact() {
    local src="$1"
    local name="$2"
    local dst="$ARTIFACT_DIR/$name"
    if [[ -f "$src" ]]; then
        cp "$src" "$dst"
    fi
    printf '%s\n' "$ARTIFACT_REL/$name"
}

bool_to_int() {
    [[ "$1" == "true" ]] && echo 1 || echo 0
}

ROOT_STRUCT="$STRUCT"
WORKSPACE_STRUCT="$(map_to_workspace_path "$ROOT_STRUCT")"
WORKSPACE_OUT="$(dirname "$OUT")"

copy_workspace "$ROOT" "$WORKSPACE"

if [[ -f "$OUT" ]]; then
    cp "$OUT" "$WORKSPACE/latest_capability_truth_prev.json"
fi

analysis_root="$WORKSPACE"
mkdir -p "$WORKSPACE_OUT"

analysis_parser_tiers_out="$WORKSPACE_OUT/parser_tiers.json"
parser_tiers_rc=$(run_cmd "$analysis_parser_tiers_out" bash generators/parser_tier_registry.sh --root "$analysis_root" --output "$analysis_parser_tiers_out" --json)
analyzer_parser=$(bool_json "$analysis_parser_tiers_out" '.ok == true and (.summary.files // 0) > 0')
parser_files=$(int_json "$analysis_parser_tiers_out" '.summary.files' 0)
parser_languages=$(int_json "$analysis_parser_tiers_out" '.summary.languages' 0)

symbols_out="$WORKSPACE_OUT/symbol_index.json"
symbols_rc=$(run_cmd "$symbols_out" bash generators/symbol_identity.sh --root "$analysis_root" --struct "$WORKSPACE_STRUCT" --output "$symbols_out" --json)
analyzer_symbols=$(bool_json "$symbols_out" '.ok == true and (.summary.symbols // 0) >= 0')
symbol_count=$(int_json "$symbols_out" '.summary.symbols' 0)

semantic_graph_out="$WORKSPACE_OUT/semantic_graph.json"
semantic_graph_rc=$(run_cmd "$semantic_graph_out" bash generators/semantic_graph.sh --root "$analysis_root" --struct "$WORKSPACE_STRUCT" --output "$semantic_graph_out" --json)
analyzer_graph=$(bool_json "$semantic_graph_out" '.summary.nodes // 0 > 0')
semantic_nodes=$(int_json "$semantic_graph_out" '.summary.nodes' 0)

analysis_ok=false
if [[ "$analyzer_parser" == true && "$analyzer_symbols" == true && "$analyzer_graph" == true ]]; then
    analysis_ok=true
fi

plan_out="$WORKSPACE_OUT/optimization_plan.json"
plan_rc=$(run_cmd "$plan_out" bash generators/optimization_plan.sh --root "$analysis_root" --struct "$WORKSPACE_STRUCT" --output-dir "$WORKSPACE_OUT/optimization" --json)
plan_ok=$(bool_json "$plan_out" '.ok == true and (.summary.actions // 0) >= 0')
plan_actions=$(int_json "$plan_out" '.summary.actions' 0)

simulation_out="$WORKSPACE_OUT/macro_simulation.json"
simulate_rc=2
simulate_ok=false
simulation_score_delta=0
simulation_changed_files=0
if [[ "$plan_ok" == true && "$plan_actions" -ge 0 ]]; then
    simulate_rc=$(run_cmd "$simulation_out" bash generators/macro_simulate.sh --plan "$plan_out" --output-dir "$WORKSPACE_OUT/simulation" --json)
    simulate_ok=$(bool_json "$simulation_out" '.ok == true')
    simulation_score_delta=$(int_json "$simulation_out" '.score.delta // 0' 0)
    simulation_changed_files=$(int_json "$simulation_out" '.summary.changed_files // 0' 0)
fi

apply_out="$WORKSPACE_OUT/macro_apply.json"
apply_rc=2
apply_ok=false
apply_backups=0
apply_skipped=0
apply_failed=0
if [[ "$plan_ok" == true && "$plan_actions" -gt 0 ]]; then
    apply_rc=$(run_cmd "$apply_out" bash generators/macro_exec.sh --plan "$plan_out" --apply --output-dir "$WORKSPACE_OUT/macro_apply" --json)
    apply_ok=$(bool_json "$apply_out" '.ok == true and .mode == "apply"')
    apply_backups=$(int_json "$apply_out" '.rollback.backups | length' 0)
    apply_skipped=$(int_json "$apply_out" '.summary.skipped' 0)
    apply_failed=$(int_json "$apply_out" '.summary.failed' 0)
fi

transaction_out="$WORKSPACE_OUT/macro_transaction.json"
transaction_rc=2
rollback_ok=false
if [[ "$plan_ok" == true ]]; then
    transaction_rc=$(run_cmd "$transaction_out" bash generators/macro_transaction.sh --plan "$plan_out" --output "$transaction_out" --json)
    rollback_ok=$(bool_json "$transaction_out" '.summary.rollback_ready == true and .summary.resumable == true and .summary.workspace_isolation == true and .ok == true')
fi

replay_out_a="$WORKSPACE_OUT/replay_a.json"
replay_out_b="$WORKSPACE_OUT/replay_b.json"
replay_rc_a=2
replay_rc_b=2
replay_ok=false
replay_hash=""
if [[ "$plan_ok" == true && "$plan_actions" -gt 0 ]]; then
    replay_rc_a=$(run_cmd "$replay_out_a" bash generators/macro_exec.sh --plan "$plan_out" --dry-run --output-dir "$WORKSPACE_OUT/replay-a" --json)
    replay_rc_b=$(run_cmd "$replay_out_b" bash generators/macro_exec.sh --plan "$plan_out" --dry-run --output-dir "$WORKSPACE_OUT/replay-b" --json)
    if [[ "$replay_rc_a" -eq 0 && "$replay_rc_b" -eq 0 ]]; then
        replay_hash_a="$(jq -c 'del(.generated_at)' "$replay_out_a" | jq -cS . | file_hash /dev/stdin 2>/dev/null || true)"
        replay_hash_b="$(jq -c 'del(.generated_at)' "$replay_out_b" | jq -cS . | file_hash /dev/stdin 2>/dev/null || true)"
        if [[ -n "$replay_hash_a" && -n "$replay_hash_b" ]]; then
            replay_hash="$replay_hash_a"
            replay_ok=$([[ "$replay_hash_a" == "$replay_hash_b" ]] && echo true || echo false)
        fi
    fi
fi

if [[ "$replay_hash" == "" ]]; then
    # fallback: fallback hash from generated path (if any)
    if [[ -f "$replay_out_a" && -f "$replay_out_b" ]]; then
        replay_hash="$(file_hash "$replay_out_a")"
    fi
fi

fixture_records="$WORKSPACE_OUT/fixtures.jsonl"
: > "$fixture_records"
fixture_total=0
fixture_supported=0
fixture_failed=0
IFS=',' read -r -a fixture_list <<< "$FIXTURES"
for fixture_root in "${fixture_list[@]}"; do
    fixture_root="$(echo "$fixture_root" | tr -d ' ')"
    [[ -z "$fixture_root" ]] && continue

    if [[ ! -d "$fixture_root" ]]; then
        fixture_total=$((fixture_total + 1))
        fixture_failed=$((fixture_failed + 1))
        jq -n --arg root "$fixture_root" --arg struct "" --arg detail "missing fixture directory" --argjson ok false \
            '{fixture_root:$root, struct:$struct, ok:$ok, detail:$detail}' >> "$fixture_records"
        continue
    fi

    fixture_root="$(cd "$fixture_root" && pwd)"
    fixture_struct="$fixture_root/struct.json"
    if [[ ! -f "$fixture_struct" ]]; then
        fixture_total=$((fixture_total + 1))
        fixture_failed=$((fixture_failed + 1))
        jq -n --arg root "$fixture_root" --arg struct "$fixture_struct" --arg detail "missing fixture struct.json" --argjson ok false \
            '{fixture_root:$root, struct:$struct, ok:$ok, detail:$detail}' >> "$fixture_records"
        continue
    fi

    fixture_safe="$(printf '%s' "$fixture_root" | tr '/.' '__')"
    fixture_parser_out="$WORKSPACE_OUT/${fixture_safe}_parser_tiers.json"
    fixture_symbol_out="$WORKSPACE_OUT/${fixture_safe}_symbols.json"
    fixture_parser_rc=$(run_cmd "$fixture_parser_out" bash generators/parser_tier_registry.sh --root "$fixture_root" --output "$fixture_parser_out" --json)
    fixture_symbol_rc=$(run_cmd "$fixture_symbol_out" bash generators/symbol_identity.sh --root "$fixture_root" --struct "$fixture_struct" --output "$fixture_symbol_out" --json)

    fixture_parser_ok=$(bool_json "$fixture_parser_out" '.ok == true and (.summary.files // 0) > 0')
    fixture_symbol_ok=$(bool_json "$fixture_symbol_out" '.ok == true and (.summary.symbols // 0) >= 0')
    fixture_files=$(int_json "$fixture_parser_out" '.summary.files' 0)
    fixture_symbols=$(int_json "$fixture_symbol_out" '.summary.symbols' 0)
    fixture_ok=$([[ "$fixture_parser_ok" == true && "$fixture_symbol_ok" == true ]] && echo true || echo false)

    fixture_total=$((fixture_total + 1))
    if [[ "$fixture_ok" == true ]]; then
        fixture_supported=$((fixture_supported + 1))
    else
        fixture_failed=$((fixture_failed + 1))
    fi

    jq -n --arg root "$fixture_root" --arg struct "$fixture_struct" --argjson ok "$fixture_ok" --argjson files "$fixture_files" --argjson symbols "$fixture_symbols" \
        --argjson parser_rc "$fixture_parser_rc" --argjson symbol_rc "$fixture_symbol_rc" \
        '{fixture_root:$root, struct:$struct, ok:$ok, parser_files:$files, symbols:$symbols, parser_tier_rc:$parser_rc, symbol_identity_rc:$symbol_rc}' >> "$fixture_records"
done

generalization_json=$(jq -s '.' "$fixture_records" 2>/dev/null || echo '[]')
if [[ "$fixture_total" -eq 0 ]]; then
    generalize_ratio=0
    generalize_ok=false
else
    generalize_ratio=$((fixture_supported * 100 / fixture_total))
    if [[ "$fixture_failed" -eq 0 ]]; then
        generalize_ok=true
    else
        generalize_ok=false
    fi
fi

analyze_capability=$analysis_ok
simulate_capability=$simulate_ok
apply_capability=false
if [[ "$simulate_capability" == true && "$apply_ok" == true ]]; then
    apply_capability=true
fi

parser_files_min=$(load_threshold '.gates.analyze.parser_files_min' 1)
parser_languages_min=$(load_threshold '.gates.analyze.parser_languages_min' 1)
symbols_min=$(load_threshold '.gates.analyze.symbol_count_min' 1)
nodes_min=$(load_threshold '.gates.analyze.semantic_nodes_min' 1)
plan_actions_min_simulate=$(load_threshold '.gates.simulate.plan_actions_min' 1)
plan_actions_min_apply=$(load_threshold '.gates.apply.plan_actions_min' 1)
generalize_ratio_min=$(load_threshold '.gates.generalization.success_ratio_min' 100)
if [[ "$parser_files" -lt "$parser_files_min" || "$parser_languages" -lt "$parser_languages_min" || "$symbol_count" -lt "$symbols_min" || "$semantic_nodes" -lt "$nodes_min" ]]; then
    analyze_capability=false
fi
if [[ "$plan_actions" -lt "$plan_actions_min_simulate" ]]; then
    simulate_capability=false
fi
if [[ "$plan_actions" -lt "$plan_actions_min_apply" || "$apply_failed" -ne 0 ]]; then
    apply_capability=false
fi
if [[ "$generalize_ratio" -lt "$generalize_ratio_min" ]]; then
    generalize_ok=false
fi

analysis_score=0
if [[ "$analyze_capability" == true ]]; then
    analysis_score=$((analysis_score + 1))
fi
if [[ "$simulate_capability" == true ]]; then
    analysis_score=$((analysis_score + 1))
fi
if [[ "$apply_capability" == true ]]; then
    analysis_score=$((analysis_score + 1))
fi
if [[ "$rollback_ok" == true ]]; then
    analysis_score=$((analysis_score + 1))
fi
if [[ "$generalize_ok" == true ]]; then
    analysis_score=$((analysis_score + 1))
fi

overall_ok=false
if [[ "$analyze_capability" == true && "$simulate_capability" == true && "$apply_capability" == true && "$rollback_ok" == true && "$generalize_ok" == true ]]; then
    overall_ok=true
fi

artifacts_parser_tiers=$(persist_artifact "$analysis_parser_tiers_out" "parser_tiers.json")
artifacts_symbol_index=$(persist_artifact "$symbols_out" "symbol_index.json")
artifacts_semantic_graph=$(persist_artifact "$semantic_graph_out" "semantic_graph.json")
artifacts_plan=$(persist_artifact "$plan_out" "optimization_plan.json")
artifacts_simulation=$(persist_artifact "$simulation_out" "macro_simulation.json")
artifacts_apply=$(persist_artifact "$apply_out" "macro_apply.json")
artifacts_transaction=$(persist_artifact "$transaction_out" "macro_transaction.json")

artifacts_parser_tiers_hash="$(file_hash "$analysis_parser_tiers_out")"
artifacts_symbol_index_hash="$(file_hash "$symbols_out")"
artifacts_semantic_graph_hash="$(file_hash "$semantic_graph_out")"
artifacts_plan_hash="$(file_hash "$plan_out")"
artifacts_simulation_hash="$(file_hash "$simulation_out")"
artifacts_apply_hash="$(file_hash "$apply_out")"
artifacts_transaction_hash="$(file_hash "$transaction_out")"

previous_exists=false
prev_ok=false
prev_analyze=false
prev_simulate=false
prev_apply=false
prev_replay=false
prev_generalization=false
prev_score=0
if [[ -f "$OUT" ]]; then
    previous_exists=true
    prev_ok="$(jq -r '.ok // false' "$OUT")"
    prev_analyze="$(jq -r '.capabilities.analyze.ok // false' "$OUT")"
    prev_simulate="$(jq -r '.capabilities.simulate.ok // false' "$OUT")"
    prev_apply="$(jq -r '.capabilities.apply.ok // false' "$OUT")"
    prev_replay="$(jq -r '.capabilities.rollback_replay.replay_ok // false' "$OUT")"
    prev_generalization="$(jq -r '.capabilities.generalization.ok // false' "$OUT")"
    prev_score="$(jq -r '.maturity.score // 0' "$OUT")"
fi

gates_passed=$(( $(bool_to_int "$analyze_capability") + $(bool_to_int "$simulate_capability") + $(bool_to_int "$apply_capability") + $(bool_to_int "$rollback_ok") + $(bool_to_int "$generalize_ok") ))
prev_gates_passed=$(( $(bool_to_int "$prev_analyze") + $(bool_to_int "$prev_simulate") + $(bool_to_int "$prev_apply") + $(bool_to_int "$prev_replay") + $(bool_to_int "$prev_generalization") ))

delta_overall=$(( $(bool_to_int "$overall_ok") - $(bool_to_int "$prev_ok") ))
delta_analyze=$(( $(bool_to_int "$analyze_capability") - $(bool_to_int "$prev_analyze") ))
delta_simulate=$(( $(bool_to_int "$simulate_capability") - $(bool_to_int "$prev_simulate") ))
delta_apply=$(( $(bool_to_int "$apply_capability") - $(bool_to_int "$prev_apply") ))
delta_replay=$(( $(bool_to_int "$replay_ok") - $(bool_to_int "$prev_replay") ))
delta_generalization=$(( $(bool_to_int "$generalize_ok") - $(bool_to_int "$prev_generalization") ))
delta_score=$(( analysis_score - prev_score ))
delta_gates=$(( gates_passed - prev_gates_passed ))

if [[ "$gates_passed" -ge 4 ]]; then
    level="advanced"
elif [[ "$gates_passed" -ge 3 ]]; then
    level="core"
elif [[ "$gates_passed" -ge 2 ]]; then
    level="intermediate"
elif [[ "$gates_passed" -ge 1 ]]; then
    level="foundational"
else
    level="none"
fi

report=$(jq -n \
  --arg schema_version "1.1" \
  --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg root "$ROOT" \
  --arg struct "$ROOT_STRUCT" \
  --arg output "$OUT" \
  --arg spec "$SPEC" \
  --arg artifacts_parser_tiers "$artifacts_parser_tiers" \
  --arg artifacts_symbol_index "$artifacts_symbol_index" \
  --arg artifacts_semantic_graph "$artifacts_semantic_graph" \
  --arg artifacts_plan "$artifacts_plan" \
  --arg artifacts_simulation "$artifacts_simulation" \
  --arg artifacts_apply "$artifacts_apply" \
  --arg artifacts_transaction "$artifacts_transaction" \
  --arg artifacts_parser_tiers_hash "$artifacts_parser_tiers_hash" \
  --arg artifacts_symbol_index_hash "$artifacts_symbol_index_hash" \
  --arg artifacts_semantic_graph_hash "$artifacts_semantic_graph_hash" \
  --arg artifacts_plan_hash "$artifacts_plan_hash" \
  --arg artifacts_simulation_hash "$artifacts_simulation_hash" \
  --arg artifacts_apply_hash "$artifacts_apply_hash" \
  --arg artifacts_transaction_hash "$artifacts_transaction_hash" \
  --argjson overall "$overall_ok" \
  --argjson analyze_capability "$analyze_capability" \
  --argjson simulate_capability "$simulate_capability" \
  --argjson apply_capability "$apply_capability" \
  --argjson rollback_ok "$rollback_ok" \
  --argjson generalize_ok "$generalize_ok" \
  --argjson parser_tiers_rc "$parser_tiers_rc" \
  --argjson symbols_rc "$symbols_rc" \
  --argjson semantic_graph_rc "$semantic_graph_rc" \
  --argjson plan_rc "$plan_rc" \
  --argjson simulation_rc "$simulate_rc" \
  --argjson apply_rc "$apply_rc" \
  --argjson transaction_rc "$transaction_rc" \
  --arg replay_rc_a "$replay_rc_a" \
  --arg replay_rc_b "$replay_rc_b" \
  --argjson replay_ok "$replay_ok" \
  --arg replay_hash "$replay_hash" \
  --argjson parser_files "$parser_files" \
  --argjson parser_languages "$parser_languages" \
  --argjson symbol_count "$symbol_count" \
  --argjson semantic_nodes "$semantic_nodes" \
  --argjson plan_actions "$plan_actions" \
  --argjson simulation_score_delta "$simulation_score_delta" \
  --argjson simulation_changed_files "$simulation_changed_files" \
  --argjson apply_backups "$apply_backups" \
  --argjson apply_skipped "$apply_skipped" \
  --argjson apply_failed "$apply_failed" \
  --argjson analysis_score "$analysis_score" \
  --argjson gates_passed "$gates_passed" \
  --argjson fixture_total "$fixture_total" \
  --argjson fixture_supported "$fixture_supported" \
  --argjson fixture_failed "$fixture_failed" \
  --argjson fixture_ratio "$generalize_ratio" \
  --argjson generalize_ratio_min "$generalize_ratio_min" \
  --argjson fixture_reports "$generalization_json" \
  --argjson parser_tiers_min "$parser_files_min" \
  --argjson parser_languages_min "$parser_languages_min" \
  --argjson symbols_min "$symbols_min" \
  --argjson nodes_min "$nodes_min" \
  --argjson previous_exists "$([ "$previous_exists" = true ] && echo 1 || echo 0)" \
  --argjson delta_overall "$delta_overall" \
  --argjson delta_analyze "$delta_analyze" \
  --argjson delta_simulate "$delta_simulate" \
  --argjson delta_apply "$delta_apply" \
  --argjson delta_replay "$delta_replay" \
  --argjson delta_generalization "$delta_generalization" \
  --argjson delta_score "$delta_score" \
  --argjson delta_gates "$delta_gates" \
  --arg level "$level" \
  --argjson prev_ok "$prev_ok" \
  --argjson prev_analyze "$prev_analyze" \
  --argjson prev_simulate "$prev_simulate" \
  --argjson prev_apply "$prev_apply" \
  --argjson prev_replay "$prev_replay" \
  --argjson prev_generalization "$prev_generalization" \
  --argjson prev_score "$prev_score" \
  '{
    schema_version:$schema_version,
    ok:$overall,
    generated_at:$generated_at,
    target:{
      root:$root,
      struct:$struct,
      output:$output
    },
    spec:$spec,
    capabilities:{
      analyze:{
        ok:$analyze_capability,
        parser_tiers:{ok:$analyze_capability, files:$parser_files, minimum:{files:$parser_tiers_min, languages:$parser_languages_min}},
        symbol_index:{ok:$analyze_capability, symbols:$symbol_count, minimum:$symbols_min},
        semantic_graph:{ok:$analyze_capability, nodes:$semantic_nodes, minimum:$nodes_min}
      },
      simulate:{
        ok:$simulate_capability,
        minimum_plan_actions:1,
        plan_exists:($plan_rc >= 0),
        plan_actions:$plan_actions,
        score_delta:$simulation_score_delta,
        changed_files:$simulation_changed_files
      },
      apply:{
        ok:$apply_capability,
        minimum_plan_actions:1,
        skipped:$apply_skipped,
        backups:$apply_backups,
        failed:$apply_failed
      },
      rollback_replay:{
        rollback_ok:$rollback_ok,
        replay_ok:$replay_ok,
        replay_hash:$replay_hash
      },
      generalization:{
        ok:$generalize_ok,
        success_ratio:$fixture_ratio,
        minimum_success_ratio:$generalize_ratio_min,
        checked_fixtures:$fixture_total,
        supported_fixtures:$fixture_supported,
        failed_fixtures:$fixture_failed,
        fixtures:$fixture_reports
      }
    },
    maturity:{
      score:$analysis_score,
      max_score:5,
      level:$level,
      gates_passed:$gates_passed
    },
    artifacts:{
      parser_tiers:{path:$artifacts_parser_tiers, hash:$artifacts_parser_tiers_hash},
      symbol_index:{path:$artifacts_symbol_index, hash:$artifacts_symbol_index_hash},
      semantic_graph:{path:$artifacts_semantic_graph, hash:$artifacts_semantic_graph_hash},
      plan:{path:$artifacts_plan, hash:$artifacts_plan_hash},
      simulation:{path:$artifacts_simulation, hash:$artifacts_simulation_hash},
      apply:{path:$artifacts_apply, hash:$artifacts_apply_hash},
      transaction:{path:$artifacts_transaction, hash:$artifacts_transaction_hash}
    },
    raw_commands:{
      parser_tier_registry_rc:$parser_tiers_rc,
      symbol_identity_rc:$symbols_rc,
      semantic_graph_rc:$semantic_graph_rc,
      optimization_plan_rc:$plan_rc,
      macro_simulate_rc:$simulation_rc,
      macro_apply_rc:$apply_rc,
      macro_transaction_rc:$transaction_rc,
      macro_replay_a_rc:($replay_rc_a|tonumber),
      macro_replay_b_rc:($replay_rc_b|tonumber)
    },
    baseline:{
      previous_exists:($previous_exists == 1),
      previous_ok:$prev_ok,
      previous_score:$prev_score
    },
    delta:{
      overall:$delta_overall,
      analyze:$delta_analyze,
      simulate:$delta_simulate,
      apply:$delta_apply,
      replay:$delta_replay,
      generalize:$delta_generalization,
      gates_passed:$delta_gates,
      score:$delta_score
    }
  }')

printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then
    printf '%s\n' "$report"
else
    jq -r '"Capability Truth Audit ok=" + (.ok|tostring) + " analyze=" + (.capabilities.analyze.ok|tostring) + " simulate=" + (.capabilities.simulate.ok|tostring) + " apply=" + (.capabilities.apply.ok|tostring) + " replay=" + (.capabilities.rollback_replay.replay_ok|tostring) + " maturity=" + (.maturity.level) + " score=" + (.maturity.score|tostring)' <<<"$report"
fi
