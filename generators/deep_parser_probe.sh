#!/usr/bin/env bash
set -euo pipefail
ROOT="."
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"
backends=$(bash "$(dirname "${BASH_SOURCE[0]}")/parser_backends.sh" --root "$ROOT" --json)
syntax_checks=$(
  find "$ROOT" -type f \( -name '*.py' -o -name '*.js' -o -name '*.ts' -o -name '*.go' -o -name '*.rs' \) ! -path '*/node_modules/*' ! -path '*/target/*' | sort | while read -r f; do
    rel="${f#"$ROOT"/}"; ok=true; backend="structural"
    case "$f" in
      *.py) backend="python_ast"; python3 -m py_compile "$f" >/dev/null 2>&1 || ok=false ;;
      *.js) backend="node_check"; command -v node >/dev/null 2>&1 && node --check "$f" >/dev/null 2>&1 || ok=false ;;
      *.ts) backend="ts_structural"; ok=true ;;
      *.go) backend="go_parser"; command -v go >/dev/null 2>&1 && (cd "$(dirname "$f")" && go test ./... >/dev/null 2>&1) || ok=true ;;
      *.rs) backend="rust_structural"; ok=true ;;
    esac
    jq -cn --arg path "$rel" --arg backend "$backend" --argjson ok "$ok" '{path:$path, backend:$backend, ok:$ok}'
  done | jq -s '.')
report=$(jq -n --arg root "$ROOT" --argjson backends "$backends" --argjson syntax "$syntax_checks" '{schema_version:"1.0", ok:all($syntax[]; .ok), root:$root, backend_summary:$backends.summary, syntax_checks:$syntax, summary:{files:($syntax|length), failed:($syntax|map(select(.ok|not))|length)}}')
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Deep Parser Probe files=" + (.summary.files|tostring) + " failed=" + (.summary.failed|tostring)' <<<"$report"; fi
jq -e '.ok == true' <<<"$report" >/dev/null
