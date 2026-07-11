#!/usr/bin/env bash
set -euo pipefail

ROOT="."
OUT="generated/intelligence/parser-tiers.json"
JSON_OUT=0
SPEC="specs/parser-tier-registry.json"

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
[[ -f "$SPEC" ]] || SPEC="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/specs/parser-tier-registry.json"
mkdir -p "$(dirname "$OUT")"

tree_available=false
command -v tree-sitter >/dev/null 2>&1 && tree_available=true
py_available=false
command -v python3 >/dev/null 2>&1 && py_available=true
go_available=false
command -v go >/dev/null 2>&1 && go_available=true

facts_file="$(mktemp)"
trap 'rm -f "$facts_file"' EXIT
: > "$facts_file"

while IFS= read -r rel; do
  ext=".${rel##*.}"
  lang=$(jq -r --arg ext "$ext" '
    .languages
    | to_entries[]
    | select((.value.extensions // []) | index($ext))
    | .key
  ' "$SPEC" | head -1)
  [[ -z "$lang" ]] && continue
  tier="structural_fallback"
  confidence="0.64"
  backend="portable_structural"
  case "$lang" in
    python)
      if [[ "$py_available" == "true" ]]; then tier="native_ast"; confidence="0.9"; backend="python_ast"; fi
      ;;
    go)
      if [[ "$go_available" == "true" ]]; then tier="native_ast"; confidence="0.9"; backend="go_parser"; fi
      ;;
    json)
      tier="native_ast"; confidence="0.92"; backend="jq_json"
      ;;
    yaml|toml)
      tier="native_ast"; confidence="0.82"; backend="structured_config"
      ;;
    *)
      if [[ "$tree_available" == "true" ]]; then tier="tree_sitter"; confidence="0.88"; backend="tree-sitter-cli"; fi
      ;;
  esac
  hash=$( (sha256sum "$ROOT/$rel" 2>/dev/null || shasum -a 256 "$ROOT/$rel") | awk '{print $1}' )
  jq -cn --arg path "$rel" --arg ext "$ext" --arg language "$lang" --arg tier "$tier" --arg backend "$backend" --arg hash "$hash" --argjson confidence "$confidence" '{
    path:$path, extension:$ext, language:$language, tier:$tier, backend:$backend,
    confidence:$confidence, backend_version:"local", invalidation_key:$hash,
    evidence:{source:"parser_tier_registry"}
  }' >> "$facts_file"
done < <(cd "$ROOT" && find . -type f \
  \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.java' -o -name '*.rb' -o -name '*.json' -o -name '*.yaml' -o -name '*.yml' -o -name '*.toml' \) \
  -not -path './.git/*' -not -path './node_modules/*' -not -path './target/*' -not -path './generated/*' | sed 's#^\./##' | sort)

report=$(jq -s --arg root "$ROOT" --slurpfile spec "$SPEC" '{
  schema_version:"1.0", ok:true, root:$root,
  spec:($spec[0] // {}),
  summary:{
    files:length,
    languages:(map(.language)|unique|length),
    native_ast:(map(select(.tier=="native_ast"))|length),
    tree_sitter:(map(select(.tier=="tree_sitter"))|length),
    lsp:(map(select(.tier=="lsp"))|length),
    structural_fallback:(map(select(.tier=="structural_fallback"))|length),
    unsupported:(map(select(.tier=="unsupported"))|length),
    low_confidence:(map(select(.confidence < 0.8))|length)
  },
  files:sort_by(.path),
  release_gate:{
    critical_low_confidence:(map(select(.confidence < 0.6))|length),
    safe_apply_floor:0.82,
    fail_closed:true
  }
}' "$facts_file")

printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then
  printf '%s\n' "$report"
else
  jq -r '"Parser tiers files=" + (.summary.files|tostring) + " fallback=" + (.summary.structural_fallback|tostring)' <<<"$report"
fi
