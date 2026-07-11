#!/usr/bin/env bash
set -euo pipefail
SPEC=""; ROOT="."; OUT="generated/intelligence/clang-adapter.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --spec) SPEC="$2"; shift 2 ;; --root) ROOT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$SPEC" && -d "$ROOT" ]] || { echo "--spec and --root required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
language="$(jq -r '.language // "cpp"' "$SPEC")"
compile_db="$ROOT/compile_commands.json"
if [[ ! -f "$compile_db" ]]; then
  jq -n --arg language "$language" '{schema_version:"1.0",ok:true,status:"review_only",available:false,native:false,decision:"review_only",language:$language,reason:"compile_commands.json is required for C/C++ translation-unit evidence",compilation_database:false,unsafe_fallback_apply:0,fail_closed:true}' > "$OUT"
elif [[ "$(jq -r '.translation_unit_resolved // false' "$SPEC")" != "true" ]]; then
  jq -n --arg language "$language" '{schema_version:"1.0",ok:true,status:"review_only",available:true,native:false,decision:"review_only",language:$language,reason:"translation unit is unresolved",compilation_database:true,unsafe_fallback_apply:0,fail_closed:true}' > "$OUT"
else
  tool="$(command -v clang-refactor 2>/dev/null || true)"
  jq -n --arg language "$language" --arg tool "$tool" '{schema_version:"1.0",ok:true,status:"review_only",available:($tool!=""),native:false,decision:"review_only",language:$language,tool:$tool,reason:"clang refactor adapter requires explicit compilation-backed recipe",compilation_database:true,unsafe_fallback_apply:0,fail_closed:true}' > "$OUT"
fi
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Clang \(.language) status=\(.status) available=\(.available)"' "$OUT"; fi
