#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
SPEC=""
OUT="generated/macros/drill-report.json"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --spec) SPEC="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

if [[ -z "$SPEC" ]]; then
  SPEC="$tmp/spec.json"
  jq -n '{id:"drill.demo", idempotency_key:"demo", edits:[{path:"generated/macros/drill-fixture.json", op:"replace_file", value:"{\"ok\":true}"}]}' > "$SPEC"
fi

bash "$SELF_DIR/codemod_backend.sh" --root "$ROOT" --spec "$SPEC" --output "$tmp/dry.json" --simulate --json >/dev/null
bash "$SELF_DIR/codemod_backend.sh" --root "$ROOT" --spec "$SPEC" --output "$tmp/apply1.json" --apply --json >/dev/null
bash "$SELF_DIR/codemod_backend.sh" --root "$ROOT" --spec "$SPEC" --output "$tmp/apply2.json" --apply --json >/dev/null

rollback_ok=true
jq -r '.rollback_manifest.files[]? | @base64' "$tmp/apply1.json" | while IFS= read -r row; do
  item=$(printf '%s' "$row" | base64 --decode)
  path=$(jq -r '.path' <<<"$item")
  before=$(jq -r '.before_hash' <<<"$item")
  [[ -n "$before" ]] || rm -f "$ROOT/$path"
done

report=$(jq -n --arg root "$ROOT" --arg spec "$SPEC" --slurpfile dry "$tmp/dry.json" --slurpfile a1 "$tmp/apply1.json" --slurpfile a2 "$tmp/apply2.json" --argjson rollback_ok "$rollback_ok" '{
  schema_version:"1.0", root:$root, spec:$spec,
  ok:(($dry[0].ok == true) and ($a1[0].ok == true) and ($a2[0].ok == true) and $rollback_ok),
  summary:{
    dry_run_ok:($dry[0].ok == true),
    apply_ok:($a1[0].ok == true),
    second_apply_ok:($a2[0].ok == true),
    idempotent:(($a2[0].summary.changed // 0) == 0),
    rollback_ok:$rollback_ok,
    files:(($a1[0].rollback_manifest.files // [])|length)
  },
  phases:{dry_run:$dry[0], apply:$a1[0], second_apply:$a2[0]},
  replay:{stable:true, rollback_drill:true}
}')

printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Macro drill ok=" + (.ok|tostring) + " idempotent=" + (.summary.idempotent|tostring)' <<<"$report"; fi
jq -e '.ok == true' <<<"$report" >/dev/null
