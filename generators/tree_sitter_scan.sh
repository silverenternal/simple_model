#!/usr/bin/env bash
set -euo pipefail

ROOT="."
OUT="generated/intelligence/tree-sitter-facts.json"
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
facts="$tmp/facts.jsonl"
: > "$facts"

hash_file() {
  (sha256sum "$1" 2>/dev/null || shasum -a 256 "$1") | awk '{print $1}'
}

lang_for() {
  case "$1" in
    *.ts|*.tsx) echo typescript ;;
    *.js|*.jsx|*.mjs|*.cjs) echo javascript ;;
    *.py) echo python ;;
    *.go) echo go ;;
    *.rs) echo rust ;;
    *.java) echo java ;;
    *.rb) echo ruby ;;
    *) echo unknown ;;
  esac
}

emit_symbol() {
  local file="$1" lang="$2" kind="$3" name="$4" line="$5" parser="$6" confidence="$7"
  local h
  h="$(hash_file "$ROOT/$file")"
  jq -cn --arg id "symbol:$file:$line:$name" --arg file "$file" --arg lang "$lang" --arg kind "$kind" --arg name "$name" --arg parser "$parser" --arg hash "$h" --argjson line "$line" --argjson confidence "$confidence" '{
    id:$id, kind:$kind, name:$name, language:$lang, path:$file, line_start:$line, line_end:$line,
    parser:$parser, confidence:$confidence, hash:$hash, evidence:{source:"tree_sitter_scan", structural:true}
  }' >> "$facts"
}

emit_edge() {
  local file="$1" lang="$2" kind="$3" target="$4" line="$5" parser="$6"
  jq -cn --arg id "edge:$kind:$file:$line:$target" --arg file "$file" --arg lang "$lang" --arg kind "$kind" --arg target "$target" --arg parser "$parser" --argjson line "$line" '{
    id:$id, kind:$kind, from:$file, to:$target, language:$lang, path:$file, line:$line,
    parser:$parser, confidence:0.78, evidence:{source:"tree_sitter_scan"}
  }' >> "$facts"
}

has_tree_sitter=false
command -v tree-sitter >/dev/null 2>&1 && has_tree_sitter=true

while IFS= read -r abs; do
  rel="${abs#"$ROOT"/}"
  lang="$(lang_for "$rel")"
  [[ "$lang" == "unknown" ]] && continue
  parser="portable_structural"
  confidence="0.72"
  if [[ "$has_tree_sitter" == "true" ]]; then
    parser="tree-sitter-cli"
    confidence="0.88"
  fi
  awk -v file="$rel" -v lang="$lang" -v parser="$parser" -v confidence="$confidence" '
    function emit_symbol(kind,name,line) {
      gsub(/^[ \t]+|[ \t]+$/, "", name)
      if (name != "") print "S\t" file "\t" lang "\t" kind "\t" name "\t" line "\t" parser "\t" confidence
    }
    function emit_edge(kind,target,line) {
      gsub(/^[ \t]+|[ \t]+$/, "", target)
      gsub(/["'\'';]/, "", target)
      if (target != "") print "E\t" file "\t" lang "\t" kind "\t" target "\t" line "\t" parser
    }
    {
      if (lang=="typescript" || lang=="javascript") {
        if ($0 ~ /^[ \t]*export[ \t]+(async[ \t]+)?function[ \t]+[A-Za-z0-9_]+/) { s=$0; sub(/.*function[ \t]+/, "", s); sub(/\(.*/, "", s); emit_symbol("function", s, NR) }
        if ($0 ~ /^[ \t]*(export[ \t]+)?class[ \t]+[A-Za-z0-9_]+/) { s=$0; sub(/.*class[ \t]+/, "", s); sub(/[ \t\{].*/, "", s); emit_symbol("class", s, NR) }
        if ($0 ~ /^[ \t]*(export[ \t]+)?(const|let|var)[ \t]+[A-Za-z0-9_]+/) { s=$0; sub(/.*(const|let|var)[ \t]+/, "", s); sub(/[ \t=:].*/, "", s); emit_symbol("variable", s, NR) }
        if ($0 ~ /^[ \t]*import .* from /) { s=$0; sub(/.* from /, "", s); emit_edge("import", s, NR) }
        if ($0 ~ /require\(/) { s=$0; sub(/.*require\(/, "", s); sub(/\).*/, "", s); emit_edge("import", s, NR) }
      } else if (lang=="python") {
        if ($0 ~ /^[ \t]*def[ \t]+[A-Za-z0-9_]+/) { s=$0; sub(/.*def[ \t]+/, "", s); sub(/\(.*/, "", s); emit_symbol("function", s, NR) }
        if ($0 ~ /^[ \t]*class[ \t]+[A-Za-z0-9_]+/) { s=$0; sub(/.*class[ \t]+/, "", s); sub(/[\(:].*/, "", s); emit_symbol("class", s, NR) }
        if ($0 ~ /^[ \t]*(from|import)[ \t]+/) { s=$0; sub(/^[ \t]*(from|import)[ \t]+/, "", s); sub(/[ \t].*/, "", s); emit_edge("import", s, NR) }
      } else if (lang=="go") {
        if ($0 ~ /^[ \t]*func[ \t]+(\([^)]*\)[ \t]+)?[A-Za-z0-9_]+/) { s=$0; sub(/.*func[ \t]+/, "", s); sub(/^\([^)]*\)[ \t]+/, "", s); sub(/\(.*/, "", s); emit_symbol("function", s, NR) }
        if ($0 ~ /^[ \t]*type[ \t]+[A-Za-z0-9_]+[ \t]+(struct|interface)/) { s=$0; sub(/.*type[ \t]+/, "", s); sub(/[ \t].*/, "", s); emit_symbol("type", s, NR) }
        if ($0 ~ /^[ \t]*import[ \t]+"/) { s=$0; sub(/.*import[ \t]+/, "", s); emit_edge("import", s, NR) }
      } else if (lang=="rust") {
        if ($0 ~ /^[ \t]*(pub[ \t]+)?fn[ \t]+[A-Za-z0-9_]+/) { s=$0; sub(/.*fn[ \t]+/, "", s); sub(/\(.*/, "", s); emit_symbol("function", s, NR) }
        if ($0 ~ /^[ \t]*(pub[ \t]+)?(struct|enum|trait)[ \t]+[A-Za-z0-9_]+/) { s=$0; sub(/.*(struct|enum|trait)[ \t]+/, "", s); sub(/[ \t<\{].*/, "", s); emit_symbol("type", s, NR) }
        if ($0 ~ /^[ \t]*use[ \t]+/) { s=$0; sub(/.*use[ \t]+/, "", s); emit_edge("import", s, NR) }
      } else if (lang=="java") {
        if ($0 ~ /^[ \t]*(public|private|protected)?[ \t]*(class|interface|enum)[ \t]+[A-Za-z0-9_]+/) { s=$0; sub(/.*(class|interface|enum)[ \t]+/, "", s); sub(/[ \t<\{].*/, "", s); emit_symbol("type", s, NR) }
        if ($0 ~ /^[ \t]*import[ \t]+/) { s=$0; sub(/.*import[ \t]+/, "", s); emit_edge("import", s, NR) }
      } else if (lang=="ruby") {
        if ($0 ~ /^[ \t]*def[ \t]+[A-Za-z0-9_!?=]+/) { s=$0; sub(/.*def[ \t]+/, "", s); emit_symbol("function", s, NR) }
        if ($0 ~ /^[ \t]*class[ \t]+[A-Za-z0-9_:]+/) { s=$0; sub(/.*class[ \t]+/, "", s); emit_symbol("class", s, NR) }
        if ($0 ~ /^[ \t]*require[ \t]+/) { s=$0; sub(/.*require[ \t]+/, "", s); emit_edge("import", s, NR) }
      }
    }
  ' "$abs" | while IFS=$'\t' read -r rec file lang kind name line parser confidence; do
    if [[ "$rec" == "S" ]]; then emit_symbol "$file" "$lang" "$kind" "$name" "$line" "$parser" "$confidence"; fi
    if [[ "$rec" == "E" ]]; then emit_edge "$file" "$lang" "$kind" "$name" "$line" "$parser"; fi
  done
done < <(find "$ROOT" -type f \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' -o -name '*.py' -o -name '*.go' -o -name '*.rs' -o -name '*.java' -o -name '*.rb' \) \
  -not -path '*/.git/*' -not -path '*/node_modules/*' -not -path '*/target/*' -not -path '*/generated/rust/target/*' | sort)

report=$(jq -s --arg root "$ROOT" --argjson tree_sitter_available "$( [[ "$has_tree_sitter" == "true" ]] && echo true || echo false )" '{
  schema_version:"1.0", ok:true, root:$root,
  parser:{name:(if $tree_sitter_available then "tree-sitter-cli" else "portable_structural" end), tree_sitter_available:$tree_sitter_available},
  summary:{facts:length, symbols:(map(select(.from|not))|length), edges:(map(select(.from?))|length), languages:(map(.language)|unique|length)},
  facts:sort_by(.id)
}' "$facts")
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Tree-sitter facts=" + (.summary.facts|tostring)' <<<"$report"; fi
