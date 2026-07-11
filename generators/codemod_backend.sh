#!/usr/bin/env bash
set -euo pipefail

ROOT="."
SPEC=""
OUT="generated/codemods/result.json"
MODE="simulate"
JSON_OUT=0
ADAPTER_DIR="codemods/adapters"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --spec) SPEC="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --adapters) ADAPTER_DIR="$2"; shift 2 ;;
    --simulate) MODE="simulate"; shift ;;
    --apply) MODE="apply"; shift ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

[[ -f "$SPEC" ]] || { echo "[FAIL] --spec required" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

adapter_for_path() {
  case "$1" in
    *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs) echo "typescript" ;;
    *.py) echo "python" ;;
    *.go) echo "go" ;;
    *.json|*.yaml|*.yml|*.toml) echo "config" ;;
    *) echo "review_only" ;;
  esac
}

adapter_meta() {
  local name="$1" file
  file="$ROOT/$ADAPTER_DIR/$name.json"
  if [[ -f "$file" ]]; then
    jq -c '.' "$file"
  else
    jq -cn --arg language "$name" '{language:$language,tier:"review_only",operations:[],formatter:"preserve",unsupported_policy:"review_only"}'
  fi
}

hash_file() {
  [[ -f "$1" ]] || { echo ""; return; }
  (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | awk '{print $1}'
}

apply_edit() {
  local edit="$1" path op value abs before after ok=true diag="" adapter adapter_json
  path=$(jq -r '.path' <<<"$edit")
  op=$(jq -r '.op // "replace_file"' <<<"$edit")
  value=$(jq -r '.value // ""' <<<"$edit")
  adapter="$(adapter_for_path "$path")"
  adapter_json="$(adapter_meta "$adapter")"
  abs="$ROOT/$path"
  before="$(hash_file "$abs")"
  mkdir -p "$(dirname "$tmp/work/$path")"
  if [[ -f "$abs" ]]; then cp "$abs" "$tmp/work/$path"; else : > "$tmp/work/$path"; fi
  case "$op" in
    replace_file) printf '%s\n' "$value" > "$tmp/work/$path" ;;
    append_line) printf '%s\n' "$value" >> "$tmp/work/$path" ;;
    json_set)
      key=$(jq -r '.key' <<<"$edit")
      jq --arg key "$key" --argjson value "$(jq '.value' <<<"$edit")" '.[$key]=$value' "$tmp/work/$path" > "$tmp/work/$path.tmp" && mv "$tmp/work/$path.tmp" "$tmp/work/$path"
      ;;
    *) ok=false; diag="unsupported op: $op; adapter produced review-only diagnostics" ;;
  esac
  case "$path" in
    *.json) jq empty "$tmp/work/$path" || { ok=false; diag="${diag} json parse failed"; } ;;
    *.py) python3 -m py_compile "$tmp/work/$path" 2>/dev/null || { ok=false; diag="${diag} python syntax failed"; } ;;
    *.go) command -v gofmt >/dev/null 2>&1 && gofmt -w "$tmp/work/$path" || true ;;
    *.rs) command -v rustfmt >/dev/null 2>&1 && rustfmt "$tmp/work/$path" >/dev/null 2>&1 || true ;;
  esac
  after="$(hash_file "$tmp/work/$path")"
  if [[ "$MODE" == "apply" && "$ok" == "true" ]]; then
    mkdir -p "$(dirname "$abs")"
    cp "$tmp/work/$path" "$abs"
  fi
  jq -cn --arg path "$path" --arg op "$op" --arg before "$before" --arg after "$after" --arg diag "$diag" --argjson ok "$ok" --argjson adapter "$adapter_json" '{
    path:$path, op:$op, ok:$ok, before_hash:$before, after_hash:$after,
    changed:($before != $after), adapter:$adapter,
    review_only:($adapter.tier == "review_only"),
    diagnostics:([ $diag ] | map(select(length>0)))
  }'
}

results=$(jq -c '.edits[]?' "$SPEC" | while IFS= read -r edit; do apply_edit "$edit"; done | jq -s 'sort_by(.path,.op)')
idempotent=true
if [[ "$(jq '[.[]|select(.ok|not)]|length' <<<"$results")" != "0" ]]; then idempotent=false; fi

report=$(jq -n --arg root "$ROOT" --arg spec "$SPEC" --arg mode "$MODE" --argjson results "$results" --arg idempotency_key "$(jq -r '.idempotency_key // empty' "$SPEC")" '{
  schema_version:"1.1", ok:all($results[]; .ok), root:$root, spec:$spec, mode:$mode,
  backend:{contract:"codemod-backend-v2", formatter_policy:"language-default", unsupported_policy:"review-only-or-fail-closed", adapter_dispatch:true},
  idempotency_key:$idempotency_key,
  summary:{edits:($results|length), changed:($results|map(select(.changed))|length), failed:($results|map(select(.ok|not))|length), review_only:($results|map(select(.review_only))|length), adapters:($results|map(.adapter.language)|unique|sort)},
  results:$results,
  rollback_manifest:{files:($results|map({path,before_hash,after_hash}))}
}')
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Codemod ok=" + (.ok|tostring) + " edits=" + (.summary.edits|tostring)' <<<"$report"; fi
jq -e '.ok == true' <<<"$report" >/dev/null
