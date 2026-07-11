#!/usr/bin/env bash
set -euo pipefail
ROOT="."; SPEC=""; OUT="generated/intelligence/native-rewrite.json"; APPLY=0; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --spec) SPEC="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --simulate) APPLY=0; shift ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -f "$SPEC" && -d "$ROOT" ]] || { echo "--root and --spec required" >&2; exit 64; }
language="$(jq -r '.language // empty' "$SPEC")"
[[ "$language" =~ ^(typescript|python|go|rust)$ ]] || { echo "unsupported native language" >&2; exit 64; }
backend="$(cd "$(dirname "${BASH_SOURCE[0]}")/../codemods/backends/$language" && pwd)/rewrite.sh"
mkdir -p "$(dirname "$OUT")" "$OUT.work"
args=(--root "$ROOT" --spec "$SPEC" --output-dir "$OUT.work" --json)
[[ "$APPLY" == 1 ]] && args+=(--apply)
report="$(bash "$backend" "${args[@]}")"
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Native rewrite language=\(.language) status=\(.status) native=\(.native)"' "$OUT"; fi
jq -e '.native==true or .status=="review_only"' "$OUT" >/dev/null
