#!/usr/bin/env bash
set -euo pipefail

ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
JSON_OUT=0
OUT="generated/intelligence/project-structure.json"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    -h|--help) echo "project_structure_miner.sh --root <repo> [--struct <struct>] [--json]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"
mkdir -p "$(dirname "$OUT")"
files=$(find "$ROOT" -type f ! -path "$ROOT/.git/*" ! -path "$ROOT/node_modules/*" ! -path "$ROOT/target/*" ! -path "$ROOT/dist/*" | sed "s#^$ROOT/##" | sort | jq -R -s 'split("\n")[:-1]')
report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --argjson files "$files" '
  def layer($p):
    if $p|test("(^|/)(api|routes|controllers?)/") then "api"
    elif $p|test("(^|/)(domain|core)/") then "domain"
    elif $p|test("(^|/)(services?|usecases?|application)/") then "application"
    elif $p|test("(^|/)(db|models?|repositories?|migrations?)/") then "persistence"
    elif $p|test("(^|/)(ui|pages|components)/") then "ui"
    elif $p|test("(^|/)(workers?|jobs?|queues?)/") then "worker"
    elif $p|test("(^|/)(infra|deploy|k8s|terraform)/") then "infrastructure"
    elif $p|test("(^|/)tests?/") then "tests"
    else "unknown" end;
  def ecosystem($p):
    if $p=="package.json" then "node"
    elif $p=="go.mod" then "go"
    elif $p=="Cargo.toml" then "rust"
    elif $p=="pyproject.toml" or $p=="requirements.txt" then "python"
    elif $p=="pom.xml" or $p=="build.gradle" or $p=="settings.gradle" then "jvm"
    else empty end;
  ($files|map(select(test("(^|/)(package.json|go.mod|Cargo.toml|pyproject.toml|requirements.txt|pom.xml|build.gradle|settings.gradle)$"))) ) as $roots
  | ($files|map({path:., layer:layer(.), generated:(test("(^|/)(generated|dist|build|target)/")), kind:(if test("(^|/)tests?/") then "test" elif test("\\.(md|txt)$") then "docs" elif test("\\.(yml|yaml|json|toml)$") then "config" else "source" end)})) as $classified
  | {
      schema_version:"1.0",
      ok:true,
      root:$root,
      struct:$struct,
      summary:{files:($files|length), workspace_roots:($roots|length), layers:($classified|map(.layer)|unique|length), generated:($classified|map(select(.generated))|length)},
      workspace_roots:($roots|map({path:., ecosystem:ecosystem(.)})),
      files:$classified,
      layer_summary:($classified|group_by(.layer)|map({layer:.[0].layer, files:length})),
      suggestions:($classified|map(select(.kind=="source" and .layer!="unknown"))|map({type:"component_candidate", path:.path, layer:.layer, confidence:0.68, reason:"path matches architectural layer convention"}))
    }')
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Project Structure files=" + (.summary.files|tostring) + " layers=" + (.summary.layers|tostring)' <<<"$report"; fi
