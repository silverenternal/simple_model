#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT=""
OUT_DIR="generated/onboard"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --output-dir) OUT_DIR="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"
mkdir -p "$OUT_DIR"
if [[ -z "$STRUCT" ]]; then
  if [[ -f "$ROOT/struct.json" ]]; then STRUCT="$ROOT/struct.json"; else STRUCT="$OUT_DIR/struct.ingested.json"; bash "$SELF_DIR/ingest_repo.sh" --root "$ROOT" --output "$STRUCT" --json >/dev/null; fi
fi
structure=$(bash "$SELF_DIR/project_structure_miner.sh" --root "$ROOT" --struct "$STRUCT" --output "$OUT_DIR/project-structure.json" --json)
audit=$(bash "$SELF_DIR/adoption_audit.sh" --root "$ROOT" --struct "$STRUCT" --json || true)
ir=$(bash "$SELF_DIR/semantic_interface_ir.sh" --root "$ROOT" --struct "$STRUCT" --output "$OUT_DIR/interface-ir.json" --json || true)
score=$(bash "$SELF_DIR/optimization_score.sh" --root "$ROOT" --struct "$STRUCT" --output-dir "$OUT_DIR" --json || true)
context=$(bash "$SELF_DIR/codex_context_pack.sh" --root "$ROOT" --struct "$STRUCT" --workflow adopt --output-dir "$OUT_DIR/context-packs" --json || true)
report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --argjson structure "$structure" --argjson audit "$audit" --argjson ir "$ir" --argjson score "$score" --argjson context "$context" '{schema_version:"1.0", ok:true, root:$root, struct:$struct, phases:{structure:$structure.summary, audit:$audit, semantic_ir:$ir.summary, score:{score:$score.score,debt:$score.debt}, context_pack:$context.workflow}, next_commands:["validate struct draft","run autopilot --dry-run","review generated context pack"]}')
printf '%s\n' "$report" > "$OUT_DIR/onboard.json"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Onboard ok=" + (.ok|tostring) + " struct=" + .struct' <<<"$report"; fi
