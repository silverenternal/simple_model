#!/usr/bin/env bash
set -euo pipefail
SPEC=""; ROOT="."; OUT="generated/intelligence/openrewrite-adapter.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --spec) SPEC="$2"; shift 2 ;; --root) ROOT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$SPEC" && -d "$ROOT" ]] || { echo "--spec and --root required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
language="$(jq -r '.language // "java"' "$SPEC")"
tool="$(command -v rewrite 2>/dev/null || command -v openrewrite 2>/dev/null || true)"
if [[ -z "$tool" ]]; then
  jq -n --arg language "$language" '{schema_version:"1.0",ok:true,status:"review_only",available:false,native:false,decision:"review_only",language:$language,reason:"OpenRewrite backend is not installed",type_attributed:false,unsafe_fallback_apply:0,fail_closed:true}' > "$OUT"
else
  jq -n --arg language "$language" --arg tool "$tool" '{schema_version:"1.0",ok:true,status:"review_only",available:true,native:false,decision:"review_only",language:$language,tool:$tool,reason:"type-attributed recipe execution requires explicit adapter configuration",type_attributed:false,unsafe_fallback_apply:0,fail_closed:true}' > "$OUT"
fi
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"OpenRewrite \(.language) status=\(.status) available=\(.available)"' "$OUT"; fi
