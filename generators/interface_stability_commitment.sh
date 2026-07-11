#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
OUT="generated/adoption/interface-stability.json"
MARKDOWN=""
GRAPH=""
GRAPH_DIFF=""
DYNAMIC=""
TESTS=""
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --markdown) MARKDOWN="$2"; shift 2 ;;
    --graph) GRAPH="$2"; shift 2 ;;
    --graph-diff) GRAPH_DIFF="$2"; shift 2 ;;
    --dynamic-edges) DYNAMIC="$2"; shift 2 ;;
    --tests) TESTS="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
STRUCT="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"
if jq -e '((.includes // []) | length) > 0' "$STRUCT" >/dev/null 2>&1; then
  resolved="$(dirname "$OUT")/.bootstrap/resolved.struct.json"
  mkdir -p "$(dirname "$resolved")"
  bash "$SELF_DIR/struct_resolve.sh" --struct "$STRUCT" --output "$resolved" >/dev/null
  STRUCT="$(cd "$(dirname "$resolved")" && pwd)/$(basename "$resolved")"
fi
[[ -f "$STRUCT" ]] || { echo "[FAIL] missing struct: $STRUCT" >&2; exit 2; }
[[ -n "$MARKDOWN" ]] || MARKDOWN="${OUT%.json}.md"
mkdir -p "$(dirname "$OUT")" "$(dirname "$MARKDOWN")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Interface drift is evidence, not a reason to suppress the commitment report.
if ! bash "$SELF_DIR/interface_scan.sh" --root "$ROOT" --struct "$STRUCT" --json > "$tmp/interfaces.json"; then
  jq empty "$tmp/interfaces.json" 2>/dev/null || jq -n '{ok:false,summary:{},components:[],findings:[]}' > "$tmp/interfaces.json"
fi
if [[ -z "$GRAPH" ]]; then
  GRAPH="$tmp/graph.json"
  [[ -n "$GRAPH_DIFF" ]] || GRAPH_DIFF="$tmp/graph-diff.json"
  bash "$SELF_DIR/semantic_graph_incremental.sh" --root "$ROOT" --struct "$STRUCT" --output "$GRAPH" --diff-output "$GRAPH_DIFF" --json >/dev/null
fi
if [[ -z "$GRAPH_DIFF" || ! -f "$GRAPH_DIFF" ]]; then
  GRAPH_DIFF="$tmp/graph-diff.json"
  jq -n '{ok:true,changed:false,summary:{source:"not-provided"}}' > "$GRAPH_DIFF"
fi
if [[ -z "$DYNAMIC" ]]; then
  DYNAMIC="$tmp/dynamic.json"
  bash "$SELF_DIR/dynamic_edge_resolver.sh" --root "$ROOT" --struct "$STRUCT" --output "$DYNAMIC" --json >/dev/null
fi
if [[ -z "$TESTS" ]]; then
  TESTS="$tmp/tests.json"
  if ! bash "$SELF_DIR/test_impact_dag.sh" --root "$ROOT" --struct "$STRUCT" --semantic-graph "$GRAPH" --output "$TESTS" --json >/dev/null 2>&1; then
    jq -n '{ok:false,summary:{tests:0},tests:[]}' > "$TESTS"
  fi
fi

report=$(jq -n \
  --arg root "$ROOT" \
  --arg struct "$STRUCT" \
  --slurpfile scan "$tmp/interfaces.json" \
  --slurpfile graph "$GRAPH" \
  --slurpfile graph_diff "$GRAPH_DIFF" \
  --slurpfile dyn "$DYNAMIC" \
  --slurpfile tests "$TESTS" \
  --slurpfile model "$STRUCT" '
  def slug($s): ($s | gsub("[^A-Za-z0-9_.:-]"; "_"));
  def rank($s): if $s=="blocked" then 5 elif $s=="deprecated" then 4 elif $s=="experimental" then 3 elif $s=="provisional" then 2 else 1 end;
  def window($s):
    if $s=="stable" then {minimum:"2 minor releases", removal_notice:"1 minor release", semver:"breaking changes require major release"}
    elif $s=="provisional" then {minimum:"next minor release", removal_notice:"before promotion", semver:"breaking changes require explicit owner approval"}
    elif $s=="deprecated" then {minimum:"1 major release", removal_notice:"required immediately", semver:"replacement must be documented"}
    elif $s=="experimental" then {minimum:"none", removal_notice:"best effort", semver:"no compatibility guarantee"}
    else {minimum:"none", removal_notice:"not applicable", semver:"changes denied until evidence is repaired"} end;
  def break_policy($s):
    if $s=="stable" then "deny unless major-version contract, migration path, affected tests, and owner approval are present"
    elif $s=="provisional" then "review required; preserve callers or provide an explicit migration"
    elif $s=="deprecated" then "only compatibility-preserving fixes and documented removal work are allowed"
    elif $s=="experimental" then "allowed after impact simulation and explicit experimental-owner approval"
    else "deny all automated interface changes until blocking evidence is resolved" end;
  ($model[0]) as $m
  | ($scan[0].components // []) as $components
  | ($dyn[0].edges // []) as $dynamic_edges
  | ($tests[0].tests // []) as $test_nodes
  | [
      $components[]? as $c
      | (($c.interfaces // []) + (($c.missing_exports // []) | map({name:.,kind:"declared_missing",path:$c.path,line:0,hash:"",parser:"declared_only"})))[]? as $i
      | ($dynamic_edges | map(select((.path // "") == ($i.path // $c.path // "")))) as $de
      | ($test_nodes | map(select(any(.semantic_selectors[]?; (.path // "") == ($i.path // $c.path // "")))) | map(.command) | unique) as $affected
      | ([ $m.modules[]? | select(.name==$c.module) | .components[]? | select(.name==$c.component) | (.owner // .owners // empty) ] | flatten | map(tostring) | unique) as $owners
      | (($i.name // "") + " " + ($i.path // "")) as $label
      | (if ($i.kind // "") == "declared_missing" or any($de[]?; .blocks_safe_apply == true) then "blocked"
         elif ($label | test("(^|[_./-])(deprecated|legacy|obsolete)([_./-]|$)";"i")) then "deprecated"
         elif ($label | test("(^|[_./-])(experimental|experiment|beta|alpha|draft)([_./-]|$)";"i")) then "experimental"
         elif (($c.undeclared_exports // []) | index($i.name)) != null or ($i.parser // "") == "regex_fallback" then "provisional"
         else "stable" end) as $status
      | {
          id:("interface:" + slug($c.module + ":" + $c.component + ":" + ($i.name // "unknown"))),
          module:$c.module, component:$c.component, name:($i.name // "unknown"), kind:($i.kind // "unknown"),
          path:($i.path // $c.path // ""), line:($i.line // 0), signature_hash:($i.hash // ""), parser:($i.parser // "unknown"),
          status:$status, status_rank:rank($status), compatibility_window:window($status), breaking_change_policy:break_policy($status),
          owners:$owners, owner_review_required:($status != "stable" or ($owners|length)==0), affected_tests:$affected,
          evidence:{interface_scan:true, semantic_graph_hash:($graph[0].graph_hash // ""), dynamic_edges:($de|map({id,trust_state,blocks_safe_apply})), graph_changed:($graph_diff[0].changed // false)},
          required_evidence:([]
            + (if ($i.kind // "") == "declared_missing" then ["implement or remove declared export"] else [] end)
            + (if any($de[]?; .blocks_safe_apply == true) then ["trusted runtime or structural evidence for dynamic edge"] else [] end)
            + (if ($i.parser // "") == "regex_fallback" then ["AST, tree-sitter, or LSP parser evidence"] else [] end)
            + (if ($owners|length)==0 then ["interface owner"] else [] end)
            + (if ($affected|length)==0 then ["interface-focused regression test"] else [] end)),
          macro_recommendations:([]
            + (if ($i.kind // "") == "declared_missing" then ["boundary-repair:reconcile-declared-export"] else [] end)
            + (if any($de[]?; .blocks_safe_apply == true) then ["surface-governance:gather-runtime-evidence"] else [] end)
            + (if ($i.parser // "") == "regex_fallback" then ["evidence-gathering:upgrade-parser-tier"] else [] end)
            + (if ($affected|length)==0 then ["test-governance:add-interface-contract-test"] else [] end))
        }
    ] as $interfaces
  | ($interfaces | group_by(.module + ":" + .component) | map(
      sort_by(-.status_rank) as $g
      | {id:("group:" + slug($g[0].module + ":" + $g[0].component)), module:$g[0].module, component:$g[0].component,
         status:$g[0].status, interfaces:($g|map(.id)), owners:($g|map(.owners[])|unique),
         affected_tests:($g|map(.affected_tests[])|unique), macro_recommendations:($g|map(.macro_recommendations[])|unique)}
    )) as $groups
  | ([ $interfaces[] | select((.owners|length)==0 or .status=="provisional" or .status=="blocked")
       | {id:("ai-leaf:" + slug(.id)), task:(if (.owners|length)==0 then "confirm interface owner" elif .status=="blocked" then "resolve missing product intent for blocked interface" else "confirm compatibility intent before promotion" end),
          interface_id:.id, inputs:[.id,.path,.status,.required_evidence], output_schema:{decision:"string",owner:"string",compatibility_window:"string"},
          may_change_structure:false, requires_human_approval:true} ] | unique_by(.id) | .[:20]) as $ai_tasks
  | {
      schema_version:"1.0", ok:true, root:$root, struct:$struct,
      summary:{interfaces:($interfaces|length), groups:($groups|length), stable:($interfaces|map(select(.status=="stable"))|length), provisional:($interfaces|map(select(.status=="provisional"))|length), experimental:($interfaces|map(select(.status=="experimental"))|length), deprecated:($interfaces|map(select(.status=="deprecated"))|length), blocked:($interfaces|map(select(.status=="blocked"))|length), ai_leaf_tasks:($ai_tasks|length)},
      readiness:(if ($interfaces|length)==0 then "evidence-incomplete" elif any($interfaces[]; .status=="blocked") then "blocked" elif any($interfaces[]; .status=="provisional") then "review-required" else "committed" end),
      interfaces:($interfaces|sort_by(.module,.component,.name)), groups:($groups|sort_by(.module,.component)), ai_leaf_tasks:$ai_tasks,
      automation_model:{macro_dominant:true, structural_decisions_by:"deterministic interface scan + semantic graph + dynamic-edge policy", ai_role:"bounded intent/owner clarification only", ai_may_apply_changes:false},
      policy:{unknown_dynamic_edges_block:true, missing_declared_exports_block:true, stable_breaking_changes_default_deny:true}
    }')

printf '%s\n' "$report" > "$OUT"
jq -r '
  "# Interface Stability Commitment", "",
  "- readiness: " + .readiness,
  "- interfaces: " + (.summary.interfaces|tostring),
  "- stable / provisional / experimental / deprecated / blocked: " + ([.summary.stable,.summary.provisional,.summary.experimental,.summary.deprecated,.summary.blocked]|map(tostring)|join(" / ")),
  "- AI leaf tasks: " + (.summary.ai_leaf_tasks|tostring), "",
  "## Interface Groups", "",
  (.groups[]? | "- " + .module + "/" + .component + ": **" + .status + "**, interfaces=" + (.interfaces|length|tostring) + ", tests=" + (.affected_tests|length|tostring)), "",
  "## Blocking Evidence", "",
  (.interfaces[]? | select(.status=="blocked") | "- " + .id + ": " + (.required_evidence|join("; "))), "",
  "## AI Leaf Clarifications", "",
  (.ai_leaf_tasks[]? | "- " + .id + ": " + .task)
' "$OUT" > "$MARKDOWN"

if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Interface stability readiness=" + .readiness + " blocked=" + (.summary.blocked|tostring)' <<<"$report"; fi
