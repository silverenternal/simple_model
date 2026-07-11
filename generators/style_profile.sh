#!/usr/bin/env bash
set -euo pipefail
ROOT="."; OUT="generated/intelligence/style-profile.json"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --root) ROOT="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
ROOT="$(cd "$ROOT" && pwd)"; mkdir -p "$(dirname "$OUT")"
protected_file="$ROOT/.simple_model/protected.json"; protected='[]'
[[ -f "$protected_file" ]] && protected="$(jq -c '.paths // []' "$protected_file")"
files="$(find "$ROOT" -type f ! -path '*/.git/*' ! -path '*/node_modules/*' | sort)"
rows="$(
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    rel="$(printf '%s' "$file" | sed "s#^$ROOT/##")"
    case "$rel" in *.ts|*.tsx) language=typescript; formatter="prettier_or_preserve" ;; *.py) language=python; formatter="python_preserve" ;; *.go) language=go; formatter="gofmt_scope" ;; *.rs) language=rust; formatter="rustfmt_scope" ;; *.json|*.yaml|*.yml|*.toml) language=config; formatter="structured_scope" ;; *) language=unknown; formatter="none" ;; esac
    generated=false; vendored=false; ignored=false; protected_flag=false
    [[ "$rel" =~ (^|/)(generated|vendor|node_modules)(/|$) ]] && generated=true
    [[ "$rel" =~ (^|/)(vendor|third_party)(/|$) ]] && vendored=true
    git -C "$ROOT" check-ignore -q "$rel" 2>/dev/null && ignored=true || true
    jq -e --arg rel "$rel" --argjson paths "$protected" '$paths|index($rel)!=null' <<<"null" >/dev/null && protected_flag=true || true
    line_ending=lf; grep -q $'\r' "$file" 2>/dev/null && line_ending=crlf || true
    indent=unknown; first_indent="$(awk 'match($0,/^[[:space:]]+/){print substr($0,RSTART,RLENGTH); exit}' "$file" 2>/dev/null || true)"; [[ -n "$first_indent" ]] && indent="$first_indent"
    quotes=double; singles="$(grep -o "'" "$file" 2>/dev/null | wc -l | tr -d ' ')"; doubles="$(grep -o '"' "$file" 2>/dev/null | wc -l | tr -d ' ')"; [[ "$singles" -gt "$doubles" ]] && quotes=single || true
    line_count="$(wc -l < "$file" | tr -d ' ')"
    jq -cn --arg path "$rel" --arg language "$language" --arg formatter "$formatter" --arg line_ending "$line_ending" --arg indent "$indent" --arg quotes "$quotes" --argjson lines "$line_count" --argjson generated "$generated" --argjson vendored "$vendored" --argjson ignored "$ignored" --argjson protected "$protected_flag" '{path:$path,language:$language,formatter:$formatter,line_ending:$line_ending,indent:$indent,quotes:$quotes,lines:$lines,generated:$generated,vendored:$vendored,ignored:$ignored,protected:$protected}'
  done <<<"$files"
)"
jq -s --arg root "$ROOT" --argjson protected "$protected" '{schema_version:"1.0",ok:true,root:$root,files:sort_by(.path),protected_paths:$protected,summary:{files:length,protected:(map(select(.protected))|length),generated:(map(select(.generated))|length),vendored:(map(select(.vendored))|length),ignored:(map(select(.ignored))|length)}}' <<<"$rows" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Style profile files=\(.summary.files) protected=\(.summary.protected)"' "$OUT"; fi
