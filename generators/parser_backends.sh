#!/usr/bin/env bash
set -euo pipefail

ROOT="."
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    -h|--help) echo "parser_backends.sh [--root <repo>] [--json]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
has(){ command -v "$1" >/dev/null 2>&1; }
version(){ "$1" --version 2>/dev/null | head -1 || true; }
count_files(){ find "$ROOT" -type f "$@" ! -path '*/.git/*' ! -path '*/node_modules/*' ! -path '*/target/*' 2>/dev/null | wc -l | tr -d ' '; }

py_files=$(count_files \( -name '*.py' \))
ts_files=$(count_files \( -name '*.ts' -o -name '*.tsx' \))
js_files=$(count_files \( -name '*.js' -o -name '*.jsx' \))
go_files=$(count_files \( -name '*.go' \))
rs_files=$(count_files \( -name '*.rs' \))
java_files=$(count_files \( -name '*.java' -o -name '*.kt' \))
cs_files=$(count_files \( -name '*.cs' \))
rb_files=$(count_files \( -name '*.rb' \))
php_files=$(count_files \( -name '*.php' \))
sh_files=$(count_files \( -name '*.sh' \))

report=$(jq -n \
  --arg root "$ROOT" \
  --argjson python "$(has python3 && echo true || echo false)" \
  --argjson node "$(has node && echo true || echo false)" \
  --argjson tsc "$(has tsc && echo true || echo false)" \
  --argjson go "$(has go && echo true || echo false)" \
  --argjson rustc "$(has rustc && echo true || echo false)" \
  --argjson cargo "$(has cargo && echo true || echo false)" \
  --arg python_version "$(version python3)" \
  --arg node_version "$(version node)" \
  --arg tsc_version "$(version tsc)" \
  --arg go_version "$(version go)" \
  --arg rustc_version "$(version rustc)" \
  --argjson py_files "$py_files" \
  --argjson ts_files "$ts_files" \
  --argjson js_files "$js_files" \
  --argjson go_files "$go_files" \
  --argjson rs_files "$rs_files" \
  --argjson java_files "$java_files" \
  --argjson cs_files "$cs_files" \
  --argjson rb_files "$rb_files" \
  --argjson php_files "$php_files" \
  --argjson sh_files "$sh_files" '
  def backend($language; $primary; $available; $version; $confidence; $fallback; $unsupported; $files; $evidence):
    {language:$language, primary:$primary, available:$available, version:$version, confidence:$confidence, fallback:$fallback, unsupported:$unsupported, repo_files:$files, evidence:$evidence};
  [
    backend("python"; "python_ast"; $python; $python_version; (if $python then 0.98 else 0.45 end); "regex_fallback"; ["dynamic setattr", "runtime monkey patching"]; $py_files; {stdlib_ast:$python}),
    backend("typescript"; "typescript_compiler_or_structural"; ($tsc or $node); (if $tsc then $tsc_version else $node_version end); (if $tsc then 0.92 elif $node then 0.78 else 0.55 end); "comment_string_aware_top_level"; ["decorator semantics without compiler metadata"]; $ts_files; {tsc:$tsc,node:$node}),
    backend("javascript"; "javascript_structural"; $node; $node_version; (if $node then 0.78 else 0.55 end); "comment_string_aware_top_level"; ["runtime export mutation"]; $js_files; {node:$node}),
    backend("go"; "go_parser"; $go; $go_version; (if $go then 0.94 else 0.60 end); "comment_string_aware_top_level"; ["build-tag-specific APIs"]; $go_files; {go_list:$go}),
    backend("rust"; "rustc_cargo_or_structural"; ($rustc or $cargo); (if $rustc then $rustc_version else "" end); (if $rustc then 0.90 else 0.60 end); "comment_string_aware_pub_scan"; ["macro-expanded APIs without cargo metadata"]; $rs_files; {rustc:$rustc,cargo:$cargo}),
    backend("java"; "jdt_or_structural"; false; ""; 0.40; "path_and_annotation_scan"; ["annotation processors", "generated sources"]; $java_files; {}),
    backend("csharp"; "roslyn_or_structural"; false; ""; 0.40; "path_and_attribute_scan"; ["source generators"]; $cs_files; {}),
    backend("ruby"; "ruby_parser_or_structural"; false; ""; 0.40; "class_method_scan"; ["metaprogramming"]; $rb_files; {}),
    backend("php"; "php_parser_or_structural"; false; ""; 0.40; "class_function_scan"; ["autoload/runtime includes"]; $php_files; {}),
    backend("shell"; "shellcheck_or_structural"; false; ""; 0.35; "function_scan"; ["sourced runtime symbols"]; $sh_files; {})
  ] as $backends
  | {
      schema_version:"1.0",
      ok:true,
      root:$root,
      summary:{languages:($backends|length), repo_languages:($backends|map(select(.repo_files > 0))|length), repo_files:($backends|map(.repo_files)|add), high_confidence:($backends|map(select(.confidence >= 0.75))|length), fallback_only:($backends|map(select(.confidence < 0.75))|length)},
      backends:$backends
    }')

if [[ "$JSON_OUT" == "1" ]]; then
  printf '%s\n' "$report"
else
  jq -r '"Parser Backends\n  languages: " + (.summary.languages|tostring) + "\n  high confidence: " + (.summary.high_confidence|tostring), (.backends[] | "  - " + .language + ": " + .primary + " confidence=" + (.confidence|tostring))' <<<"$report"
fi
