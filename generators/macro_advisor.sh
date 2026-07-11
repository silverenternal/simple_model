#!/usr/bin/env bash
set -euo pipefail

ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
COCKPIT=""
OUT="generated/macros/advisor-report.json"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --cockpit) COCKPIT="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"
STRUCT="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if [[ -z "$COCKPIT" || ! -f "$COCKPIT" ]]; then bash "$(dirname "$0")/macro_cockpit.sh" --output-dir "$tmp/cockpit" --json >/dev/null; COCKPIT="$tmp/cockpit/cockpit.json"; fi
dirty=0
if command -v git >/dev/null 2>&1 && git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then dirty=$(git -C "$ROOT" status --short 2>/dev/null | wc -l | tr -d ' '); fi
report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --argjson dirty "$dirty" --slurpfile cockpit "$COCKPIT" '{
  schema_version:"1.0", ok:true, root:$root, struct:$struct,
  worktree:{dirty_files:$dirty, apply_advice_allowed:($dirty == 0)},
  lists:{
    safe_now:(if $dirty == 0 then ($cockpit[0].top_safe_actions // []) else [] end),
    simulate_first:($cockpit[0].top_safe_actions // []),
    review_first:($cockpit[0].top_review_actions // []),
    gather_evidence:($cockpit[0].top_evidence_gaps // []),
    avoid:(if $dirty > 0 then [{reason:"dirty_worktree", command:"commit_or_stash_before_apply"}] else [] end)
  },
  next_commands:[
    "simple_model_pi.sh macro-cockpit --json",
    "simple_model_pi.sh macro-preconditions --json",
    "simple_model_pi.sh macro-drill --json",
    "simple_model_pi.sh macro-advisor --json"
  ],
  policy:{no_network:true, no_global_state:true, dirty_worktree_blocks_apply:true}
}')
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Macro advisor dirty_files=" + (.worktree.dirty_files|tostring)' <<<"$report"; fi
