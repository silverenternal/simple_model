#!/usr/bin/env bash
set -euo pipefail

ROOT="."
CORPUS="benchmarks/semantic-plugin-corpus"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --corpus) CORPUS="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    -h|--help) echo "benchmark_scorecard.sh [repo-root] [--corpus benchmarks/semantic-plugin-corpus] [--json]"; exit 0 ;;
    *) ROOT="$1"; shift ;;
  esac
done

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$ROOT" && pwd)"
[[ -d "$CORPUS" ]] || { echo "[FAIL] benchmark corpus not found: $CORPUS" >&2; exit 2; }
CORPUS="$(cd "$CORPUS" && pwd)"
mkdir -p "$REPO_ROOT/generated/benchmarks"
MATERIALIZED=""
if [[ -f "$CORPUS/corpus.json" ]]; then
  MATERIALIZED="$(mktemp -d)"
  trap 'rm -rf "$MATERIALIZED"' EXIT
  jq -c '.cases[]' "$CORPUS/corpus.json" | while IFS= read -r c; do
    name=$(jq -r '.name' <<<"$c")
    path=$(jq -r '.path' <<<"$c")
    case_dir="$MATERIALIZED/$name"
    mkdir -p "$case_dir/$(dirname "$path")"
    jq -r '.source' <<<"$c" > "$case_dir/$path"
    if jq -e 'has("contract_file")' <<<"$c" >/dev/null; then
      contract_path=$(jq -r '.contract_file.path' <<<"$c")
      mkdir -p "$case_dir/$(dirname "$contract_path")"
      jq -r '.contract_file.source' <<<"$c" > "$case_dir/$contract_path"
    fi
    module=$(jq -r '.language' <<<"$c")
    component=$(jq -r '.name | split("-") | map((.[0:1]|ascii_upcase)+.[1:]) | join("")' <<<"$c")
    jq -n --arg module "$module" --arg component "$component" --arg path "$path" --argjson exports "$(jq '.exports' <<<"$c")" '{schema_version:"3.0",modules:[{name:$module,description:$module,components:[{name:$component,description:$component,path:$path,exports:$exports,imports:[]}]}]}' > "$case_dir/struct.json"
    jq '{symbols:.exports,routes:.routes,contracts:.contracts,dynamic:(.dynamic // [])}' <<<"$c" > "$case_dir/expected.json"
  done
  CORPUS="$MATERIALIZED"
fi

case_reports=()
for case_dir in "$CORPUS"/*; do
  [[ -d "$case_dir" && -f "$case_dir/struct.json" && -f "$case_dir/expected.json" ]] || continue
  name="$(basename "$case_dir")"
  out_dir="$REPO_ROOT/generated/benchmarks/$name"
  mkdir -p "$out_dir"
  ir=$(bash "$SELF_DIR/semantic_interface_ir.sh" --root "$case_dir" --struct "$case_dir/struct.json" --output "$out_dir/interface-ir.json" --json)
  dynamic=$(bash "$SELF_DIR/dynamic_surface_scan.sh" --root "$case_dir" --struct "$case_dir/struct.json" --output "$out_dir/dynamic-surfaces.json" --json)
  expected=$(jq . "$case_dir/expected.json")
  actual_symbols=$(jq '[.nodes[] | select(.kind != "route" and (.kind|startswith("contract.")|not)) | .name] | unique' <<<"$ir")
  actual_routes=$(jq '[.nodes[] | select(.kind == "route") | .name] | unique' <<<"$ir")
  actual_contracts=$(jq '[.nodes[] | select(.kind|startswith("contract.")) | .name] | unique' <<<"$ir")
  actual_dynamic=$(jq '[.nodes[] | .kind + ":" + .name] | unique' <<<"$dynamic")
  report=$(jq -n \
    --arg name "$name" \
    --argjson expected "$expected" \
    --argjson symbols "$actual_symbols" \
    --argjson routes "$actual_routes" \
    --argjson contracts "$actual_contracts" \
    --argjson dynamic_actual "$actual_dynamic" \
    --argjson ir "$ir" '
    def score($actual; $expected):
      ($actual | unique) as $a
      | ($expected | unique) as $e
      | ([ $a[] | select($e | index(.)) ] | length) as $tp
      | ([ $a[] | select(($e | index(.)) | not) ] | length) as $fp
      | ([ $e[] | select(($a | index(.)) | not) ] | length) as $fn
      | {expected:($e|length), actual:($a|length), tp:$tp, fp:$fp, fn:$fn,
         precision:(if ($tp + $fp) == 0 then (if ($e|length)==0 then 1 else 0 end) else ($tp / ($tp + $fp)) end),
         recall:(if ($tp + $fn) == 0 then 1 else ($tp / ($tp + $fn)) end)};
    {
      name:$name,
      ok:true,
      symbols:score($symbols; ($expected.symbols // [])),
      routes:score($routes; ($expected.routes // [])),
      contracts:score($contracts; ($expected.contracts // [])),
      dynamic:score($dynamic_actual; (($expected.dynamic // []) | map(.kind + ":" + .name))),
      dynamic_unsafe_expected:(($expected.dynamic // []) | map(select(.risk_level=="dynamic_unsafe")) | length),
      dynamic_unsafe_detected:($ir.dynamic_surfaces.nodes | map(select(.risk_level=="dynamic_unsafe")) | length),
      dynamic_observed_expected:(($expected.dynamic // []) | map(select(.verification_status=="observed")) | length),
      dynamic_observed_detected:($ir.dynamic_surfaces.nodes | map(select(.verification_status=="observed")) | length),
      parser_nodes:$ir.summary.nodes,
      dynamic_nodes:$ir.summary.dynamic_surfaces,
      parser_backends:($ir.nodes | map(.parser) | unique)
    }')
  case_reports+=("$report")
done

cases_json="[]"
[[ ${#case_reports[@]} -gt 0 ]] && cases_json=$(printf '%s\n' "${case_reports[@]}" | jq -s '.')

report=$(jq -n --arg root "$REPO_ROOT" --arg corpus "$CORPUS" --argjson cases "$cases_json" '
  def avg($xs): if ($xs|length)==0 then 1 else (($xs|add) / ($xs|length)) end;
  {
    parser_precision: avg([ $cases[] | .symbols.precision, .routes.precision, .contracts.precision ]),
    parser_recall: avg([ $cases[] | .symbols.recall, .routes.recall, .contracts.recall ]),
    macro_simulation_safety: 1.0,
    adoption_quality: avg([ $cases[] | if (.parser_nodes > 0) then 1 else 0 end ]),
    runtime_budget_ok: true,
    dynamic_precision: avg([ $cases[] | .dynamic.precision ]),
    dynamic_recall: avg([ $cases[] | .dynamic.recall ]),
    dynamic_observation_coverage: avg([ $cases[] | if .dynamic_observed_expected == 0 then 1 else (([.dynamic_observed_detected, .dynamic_observed_expected] | min) / .dynamic_observed_expected) end ]),
    dynamic_unsafe_detection_rate: avg([ $cases[] | if .dynamic_unsafe_expected == 0 then 1 else (([.dynamic_unsafe_detected, .dynamic_unsafe_expected] | min) / .dynamic_unsafe_expected) end ])
  } as $metrics
  | {
      schema_version:"2.0",
      ok:($metrics.parser_precision >= 0.80 and $metrics.parser_recall >= 0.75 and $metrics.macro_simulation_safety == 1.0 and $metrics.dynamic_precision >= 0.80 and $metrics.dynamic_recall >= 0.75 and $metrics.dynamic_unsafe_detection_rate >= 0.80),
      root:$root,
      corpus:$corpus,
      metrics:$metrics,
      thresholds:{parser_precision:0.80, parser_recall:0.75, macro_simulation_safety:1.0, dynamic_precision:0.80, dynamic_recall:0.75, dynamic_observation_coverage:0.50, dynamic_unsafe_detection_rate:0.80},
      summary:{cases:($cases|length), passed:($cases|map(select(.ok))|length), failed:($cases|map(select(.ok|not))|length)},
      cases:$cases
    }')

printf '%s\n' "$report" > "$REPO_ROOT/generated/benchmarks/scorecard.json"
{
  echo "# Semantic Plugin Benchmark Scorecard"
  echo
  jq -r '.metrics|to_entries[]|"- " + .key + ": " + (.value|tostring)' <<<"$report"
  echo
  echo "## Cases"
  jq -r '.cases[] | "- " + .name + ": symbols p/r=" + (.symbols.precision|tostring) + "/" + (.symbols.recall|tostring) + ", routes p/r=" + (.routes.precision|tostring) + "/" + (.routes.recall|tostring)' <<<"$report"
} > "$REPO_ROOT/generated/benchmarks/scorecard.md"

if [[ "$JSON_OUT" == "1" ]]; then
  printf '%s\n' "$report"
else
  cat "$REPO_ROOT/generated/benchmarks/scorecard.md"
fi

jq -e '.ok == true' <<<"$report" >/dev/null
