#!/usr/bin/env bash
set -euo pipefail

ROOT="."
OUT="generated/intelligence/lsp-symbols.json"
TIMEOUT=5
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --timeout) TIMEOUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
mkdir -p "$(dirname "$OUT")"

servers=$(jq -n \
  --argjson ts "$(command -v typescript-language-server >/dev/null 2>&1 && echo true || echo false)" \
  --argjson pyright "$(command -v pyright-langserver >/dev/null 2>&1 && echo true || echo false)" \
  --argjson gopls "$(command -v gopls >/dev/null 2>&1 && echo true || echo false)" \
  --argjson rust "$(command -v rust-analyzer >/dev/null 2>&1 && echo true || echo false)" \
  '{typescript:$ts, python:$pyright, go:$gopls, rust:$rust}')

# LSP protocol orchestration is intentionally opt-in. For production safety we
# do not spawn long-lived language servers unless the repo has explicit tooling.
symbols=$(find "$ROOT" -maxdepth 4 -type f \( -name 'tsconfig.json' -o -name 'pyproject.toml' -o -name 'go.mod' -o -name 'Cargo.toml' \) \
  -not -path '*/.git/*' -not -path '*/generated/rust/target/*' | sort | while IFS= read -r f; do
    rel="${f#"$ROOT"/}"
    case "$rel" in
      *tsconfig.json) lang=typescript; available=$(jq -r '.typescript' <<<"$servers") ;;
      *pyproject.toml) lang=python; available=$(jq -r '.python' <<<"$servers") ;;
      *go.mod) lang=go; available=$(jq -r '.go' <<<"$servers") ;;
      *Cargo.toml) lang=rust; available=$(jq -r '.rust' <<<"$servers") ;;
      *) lang=unknown; available=false ;;
    esac
    jq -cn --arg id "workspace:$rel" --arg path "$rel" --arg language "$lang" --argjson available "$available" --argjson timeout "$TIMEOUT" '{
      id:$id, path:$path, language:$language, lsp_available:$available, timeout_seconds:$timeout,
      symbols:[], references:[], definitions:[],
      diagnostics:(if $available then ["lsp server detected; protocol indexing can be enabled by policy"] else ["lsp server unavailable; using structural parser evidence"] end)
    }'
  done | jq -s 'sort_by(.id)')

report=$(jq -n --arg root "$ROOT" --argjson servers "$servers" --argjson workspaces "$symbols" '{
  schema_version:"1.0", ok:true, root:$root, mode:"safe-discovery",
  servers:$servers,
  summary:{workspaces:($workspaces|length), available:($workspaces|map(select(.lsp_available))|length), symbols:($workspaces|map(.symbols|length)|add // 0)},
  workspaces:$workspaces
}')
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"LSP workspaces=" + (.summary.workspaces|tostring) + " available=" + (.summary.available|tostring)' <<<"$report"; fi
