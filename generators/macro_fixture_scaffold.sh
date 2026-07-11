#!/usr/bin/env bash
set -euo pipefail
MACRO_ID="example.macro"; OUT_DIR="generated/macros/fixtures"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --macro-id) MACRO_ID="$2"; shift 2 ;; --output-dir) OUT_DIR="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
mkdir -p "$OUT_DIR"
for kind in positive negative adversarial partial_parse dirty_worktree rollback; do
  jq -n --arg id "$MACRO_ID" --arg kind "$kind" '{schema_version:"1.0",macro_id:$id,fixture_id:($kind+"-fixture"),kind:$kind,proofs:{match_precision:true,bounded_effects:true,idempotency:true,rollback:true,composition:true,test_impact:true,performance:true,external_generality:true},expected:{decision:(if $kind=="negative" or $kind=="adversarial" or $kind=="partial_parse" or $kind=="dirty_worktree" then "review_only" else "accept" end),write_paths:["src"]},observations:{affected_tests:["fixture-test"],duration_ms:1,external_repo:true}}' > "$OUT_DIR/$kind.json"
done
jq -n --arg macro_id "$MACRO_ID" --arg dir "$OUT_DIR" '{schema_version:"1.0",ok:true,macro_id:$macro_id,fixture_dir:$dir,required_kinds:["positive","negative","adversarial","partial_parse","dirty_worktree","rollback"],files:["positive.json","negative.json","adversarial.json","partial_parse.json","dirty_worktree.json","rollback.json"]}' > "$OUT_DIR/manifest.json"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT_DIR/manifest.json"; else jq -r '"Macro fixtures \(.macro_id) count=\(.files|length)"' "$OUT_DIR/manifest.json"; fi
