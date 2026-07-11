#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLAN="generated/optimization/plan.json"
OUT_DIR="generated/optimization"
JOBS=1
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) PLAN="$2"; shift 2 ;;
    --output-dir) OUT_DIR="$2"; shift 2 ;;
    --jobs) JOBS="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -f "$PLAN" ]] || { echo "[FAIL] plan not found: $PLAN" >&2; exit 2; }
mkdir -p "$OUT_DIR"
ROOT="$(jq -r '.root' "$PLAN")"
STRUCT="$(jq -r '.struct' "$PLAN")"
partition_file="$OUT_DIR/macro-simulation-partitions.json"
jq --argjson jobs "$JOBS" '
  def writes($a): (($a.writes // []) + [($a.target.path // empty)] | map(select(. != "")) | unique);
  (.actions // []) as $actions
  | [range(0; ($actions|length)) as $i | $actions[$i] + {ordinal:$i, write_set:writes($actions[$i])}] as $stable
  | {
      schema_version:"1.0",
      ok:true,
      jobs:$jobs,
      mode:"simulation_only",
      apply_allowed:false,
      candidates:$stable,
      partitions:(
        reduce $stable[] as $a ([]; 
          (map(select(any(.write_set[]?; . as $w | any($a.write_set[]?; . == $w)))) | length) as $conflicting
          | if $conflicting == 0 then . + [{id:("partition-" + ((length+1)|tostring)), actions:[$a.id], write_set:$a.write_set}]
            else . + [{id:("serial-conflict-" + (($a.ordinal+1)|tostring)), actions:[$a.id], write_set:$a.write_set, reason:"write_set_conflict"}]
            end
        )
      )
    }' "$PLAN" > "$partition_file"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo"
if command -v rsync >/dev/null 2>&1; then
  rsync -a \
    --exclude '.git/' \
    --exclude 'node_modules/' \
    --exclude 'target/' \
    --exclude 'dist/' \
    --exclude 'build/' \
    --exclude '.venv/' \
    --exclude '__pycache__/' \
    "$ROOT/" "$tmp/repo/"
else
  (cd "$ROOT" && find . \
    -path './.git' -prune -o \
    -path './node_modules' -prune -o \
    -path './target' -prune -o \
    -path './dist' -prune -o \
    -path './build' -prune -o \
    -path './.venv' -prune -o \
    -path './__pycache__' -prune -o \
    -type f -print) | while IFS= read -r rel; do
      mkdir -p "$tmp/repo/$(dirname "$rel")"
      cp "$ROOT/$rel" "$tmp/repo/$rel"
    done
fi
sim_struct="$tmp/repo/${STRUCT#"$ROOT"/}"
[[ -f "$sim_struct" ]] || sim_struct="$STRUCT"
before_file="$tmp/before.json"
after_file="$tmp/after.json"
execution_file="$tmp/execution.json"
diffs_file="$tmp/diffs.json"
dynamic_before_file="$tmp/dynamic-before.json"
dynamic_after_file="$tmp/dynamic-after.json"
bash "$SELF_DIR/optimization_score.sh" --root "$ROOT" --struct "$STRUCT" --output-dir "$OUT_DIR" --json > "$before_file" 2>/dev/null || jq -n '{score:0,debt:0}' > "$before_file"
bash "$SELF_DIR/dynamic_surface_scan.sh" --root "$ROOT" --struct "$STRUCT" --output "$OUT_DIR/dynamic-surfaces.before.json" --json > "$dynamic_before_file" 2>/dev/null || jq -n '{nodes:[],summary:{nodes:0}}' > "$dynamic_before_file"
sim_plan="$tmp/plan.json"
jq --arg root "$tmp/repo" --arg struct "$sim_struct" '.root=$root | .struct=$struct' "$PLAN" > "$sim_plan"
bash "$SELF_DIR/macro_exec.sh" --plan "$sim_plan" --apply --output-dir "$tmp/optimization" --json > "$execution_file" 2>/dev/null || true
[[ -s "$execution_file" ]] || jq -n '{ok:false,summary:{actions:0,failed:1},results:[]}' > "$execution_file"
bash "$SELF_DIR/optimization_score.sh" --root "$tmp/repo" --struct "$sim_struct" --output-dir "$tmp/optimization" --json > "$after_file" 2>/dev/null || jq -n '{score:0,debt:0}' > "$after_file"
bash "$SELF_DIR/dynamic_surface_scan.sh" --root "$tmp/repo" --struct "$sim_struct" --output "$tmp/optimization/dynamic-surfaces.after.json" --json > "$dynamic_after_file" 2>/dev/null || jq -n '{nodes:[],summary:{nodes:0}}' > "$dynamic_after_file"
(cd "$tmp/repo" && find . -type f | sort | sed 's#^\./##' | while read -r f; do
  [[ -f "$ROOT/$f" ]] || { jq -cn --arg path "$f" '{path:$path, status:"added"}'; continue; }
  a=$( (sha256sum "$ROOT/$f" 2>/dev/null || shasum -a 256 "$ROOT/$f") | awk '{print $1}' )
  b=$( (sha256sum "$tmp/repo/$f" 2>/dev/null || shasum -a 256 "$tmp/repo/$f") | awk '{print $1}' )
  [[ "$a" == "$b" ]] || jq -cn --arg path "$f" --arg before "$a" --arg after "$b" '{path:$path, status:"changed", before:$before, after:$after}'
done | jq -s '.') > "$diffs_file"
report=$(jq -n --arg plan "$PLAN" --arg root "$ROOT" --arg struct "$STRUCT" --slurpfile before_file "$before_file" --slurpfile after_file "$after_file" --slurpfile execution_file "$execution_file" --slurpfile diffs_file "$diffs_file" --slurpfile dynamic_before_file "$dynamic_before_file" --slurpfile dynamic_after_file "$dynamic_after_file" '
  ($before_file[0] // {score:0,debt:0}) as $before
  | ($after_file[0] // {score:0,debt:0}) as $after
  | ($execution_file[0] // {ok:false,summary:{actions:0,failed:1},results:[]}) as $execution
  | ($diffs_file[0] // []) as $diffs
  | ($dynamic_before_file[0] // {nodes:[],summary:{nodes:0}}) as $dynamic_before
  | ($dynamic_after_file[0] // {nodes:[],summary:{nodes:0}}) as $dynamic_after
  | {
  schema_version:"1.0",
  ok:($execution.ok == true),
  mode:"simulation",
  plan:$plan,
  root:$root,
  struct:$struct,
  score:{before:($before.score // 0), after:($after.score // 0), delta:(($after.score // 0)-($before.score // 0)), debt_before:($before.debt // 0), debt_after:($after.debt // 0)},
  summary:{actions:($execution.summary.actions // 0), changed_files:($diffs|length), failed:($execution.summary.failed // 0)},
  concurrency:{
    jobs:($ARGS.named.jobs|tonumber),
    mode:"simulation_only",
    partitions:($ARGS.named.partitions|fromjson).partitions,
    refused_apply:true,
    stable_aggregation:true
  },
  diffs:$diffs,
  dynamic:{
    before:$dynamic_before.summary,
    after:$dynamic_after.summary,
    affected_nodes:(
      ($dynamic_before.nodes // [])
      | map(. as $node | select(
          ($diffs | any(. as $d | $d.path == $node.path or ($d.path|endswith($node.path)) or ($node.path|endswith($d.path))))
          or (($execution.results // []) | any((.action.writes // []) | any(. == $node.path or (. | endswith($node.path)) or ($node.path | endswith(.)))))
          or (($execution.results // []) | any((.action.target.path // "") as $p | $p == $node.path or ($p|endswith($node.path)) or ($node.path|endswith($p))))
          or (($execution.results // []) | any((.action.target.component // "") != "" and (.action.target.component // "") == ($node.component // "")))
          or (($execution.error // "") == "macro_policy_denied" and (($execution.evidence // "") | contains($node.id)))
        ))
    ),
    missing_observations:(
      ($dynamic_before.nodes // [])
      | map(. as $node | select(.verification_status != "observed" and (
          ($diffs | any(. as $d | $d.path == $node.path or ($d.path|endswith($node.path)) or ($node.path|endswith($d.path))))
          or (($execution.error // "") == "macro_policy_denied" and (($execution.evidence // "") | contains($node.id)))
        )))
    ),
    unsafe_nodes:(
      ($dynamic_before.nodes // [])
      | map(. as $node | select(.risk_level == "dynamic_unsafe" and (
          ($diffs | any(. as $d | $d.path == $node.path or ($d.path|endswith($node.path)) or ($node.path|endswith($d.path))))
          or (($execution.error // "") == "macro_policy_denied" and (($execution.evidence // "") | contains($node.id)))
        )))
    )
  },
  execution:$execution,
  rollback_feasible:true
}' --arg jobs "$JOBS" --arg partitions "$(cat "$partition_file")")
printf '%s\n' "$report" > "$OUT_DIR/simulation.json"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Macro Simulation ok=" + (.ok|tostring) + " delta=" + (.score.delta|tostring) + " changed=" + (.summary.changed_files|tostring)' <<<"$report"; fi
jq -e '.ok == true' <<<"$report" >/dev/null
