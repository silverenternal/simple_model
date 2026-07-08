#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST_FILE="${SCRIPT_DIR}/../references/command-manifest.json"

usage() {
    cat <<'USAGE'
simple_model_pi.sh [--target-root PATH] [--struct PATH] <command> [args]

Global options:
  --target-root PATH       Repository to analyze. Defaults to current directory.
  --struct PATH            struct.json to use. Defaults to <target-root>/struct.json, then simple_model/struct.json.
  --simple-model-home PATH Toolchain checkout. Defaults to SIMPLE_MODEL_HOME or auto-discovery.
  --json                   Machine-readable output for commands that support it.

Commands:
  doctor                   Diagnose plugin, toolchain, and target repo readiness.
  commands                 List wrapper command metadata. Use --json for machine-readable output.
  validate                 Run validate/check/lint/drift summaries on simple_model.
  full-check               Run validate/check/lint/drift and tests/test_*.sh.
  ingest [repo] [out]      Draft struct.json from an existing repo.
  audit [repo]             Audit unmanaged source files.
  interfaces [repo]        Scan public interfaces against struct.json.
  facts [repo]             Emit generated/.ai/code_facts.json.
  pr-gate [repo] [files]   Run PR impact, drift gates, risk, tests, review route.
  dashboard [out]          Generate static dashboard HTML.
  resolve                  Resolve multi-file struct includes.
USAGE
}

find_simple_model_home() {
    local explicit="${SIMPLE_MODEL_HOME:-}"
    if [[ -n "$explicit" ]]; then
        if [[ -x "$explicit/bootstrap.sh" && -d "$explicit/generators" ]]; then
            cd "$explicit" && pwd
            return 0
        fi
        echo "[FAIL] SIMPLE_MODEL_HOME is not a simple_model checkout: $explicit" >&2
        return 2
    fi

    local d="$PWD"
    while [[ "$d" != "/" ]]; do
        if [[ -x "$d/bootstrap.sh" && -d "$d/generators" ]]; then
            printf '%s\n' "$d"
            return 0
        fi
        d="$(dirname "$d")"
    done

    d="$(cd "$SCRIPT_DIR/../../.." && pwd)"
    if [[ -x "$d/bootstrap.sh" && -d "$d/generators" ]]; then
        printf '%s\n' "$d"
        return 0
    fi

    d="$(cd "$SCRIPT_DIR/../../../../../.." && pwd)"
    if [[ -x "$d/bootstrap.sh" && -d "$d/generators" ]]; then
        printf '%s\n' "$d"
        return 0
    fi

    echo "[FAIL] cannot locate simple_model root. Set SIMPLE_MODEL_HOME=/path/to/simple_model" >&2
    return 2
}

json_bool() {
    if "$@" >/dev/null 2>&1; then printf 'true'; else printf 'false'; fi
}

doctor() {
    local json="$1"
    local bash_major="${BASH_VERSINFO[0]:-0}"
    local has_jq has_git has_codex has_gh home_ok target_ok struct_ok marketplace_ok plugin_ok
    has_jq=$(json_bool command -v jq)
    has_git=$(json_bool command -v git)
    has_codex=$(json_bool command -v codex)
    has_gh=$(json_bool command -v gh)
    home_ok=$(json_bool test -x "$SIMPLE_HOME/bootstrap.sh")
    target_ok=$(json_bool test -d "$TARGET_ROOT")
    struct_ok=$(json_bool test -f "$STRUCT_PATH")
    marketplace_ok=$(json_bool jq empty "$SIMPLE_HOME/.agents/plugins/marketplace.json")
    plugin_ok=$(json_bool jq empty "$SIMPLE_HOME/plugins/simple-model-project-intelligence/.codex-plugin/plugin.json")
    local hard_fail=false
    [[ "$bash_major" -ge 4 && "$has_jq" == "true" && "$has_git" == "true" && "$home_ok" == "true" && "$target_ok" == "true" ]] || hard_fail=true

    if [[ "$json" == "1" ]]; then
        jq -n \
          --arg simple_model_home "$SIMPLE_HOME" \
          --arg target_root "$TARGET_ROOT" \
          --arg struct "$STRUCT_PATH" \
          --argjson bash_major "$bash_major" \
          --argjson has_jq "$has_jq" \
          --argjson has_git "$has_git" \
          --argjson has_codex "$has_codex" \
          --argjson has_gh "$has_gh" \
          --argjson home_ok "$home_ok" \
          --argjson target_ok "$target_ok" \
          --argjson struct_ok "$struct_ok" \
          --argjson marketplace_ok "$marketplace_ok" \
          --argjson plugin_ok "$plugin_ok" \
          --argjson ok "$( [[ "$hard_fail" == "false" ]] && echo true || echo false )" \
          '{
            ok:$ok,
            simple_model_home:$simple_model_home,
            target_root:$target_root,
            struct:$struct,
            checks:{
              bash_major:$bash_major,
              jq:$has_jq,
              git:$has_git,
              codex_optional:$has_codex,
              gh_optional:$has_gh,
              simple_model_home:$home_ok,
              target_root:$target_ok,
              struct:$struct_ok,
              marketplace_json:$marketplace_ok,
              plugin_manifest:$plugin_ok
            },
            hints: (
              []
              + (if $bash_major < 4 then ["Install bash >= 4 and run with that shell."] else [] end)
              + (if $has_jq then [] else ["Install jq."] end)
              + (if $home_ok then [] else ["Set SIMPLE_MODEL_HOME=/path/to/simple_model."] end)
              + (if $target_ok then [] else ["Pass --target-root /path/to/repo."] end)
              + (if $struct_ok then [] else ["Pass --struct /path/to/struct.json or create one with ingest."] end)
            )
          }'
    else
        echo "simple_model doctor"
        echo "  simple_model_home: $SIMPLE_HOME"
        echo "  target_root      : $TARGET_ROOT"
        echo "  struct           : $STRUCT_PATH"
        echo "  bash_major       : $bash_major"
        echo "  jq               : $has_jq"
        echo "  git              : $has_git"
        echo "  codex optional   : $has_codex"
        echo "  gh optional      : $has_gh"
        echo "  marketplace      : $marketplace_ok"
        echo "  plugin manifest  : $plugin_ok"
    fi
    [[ "$hard_fail" == "false" ]]
}

JSON_OUT=0
TARGET_ROOT="$PWD"
STRUCT_PATH=""
HOME_OVERRIDE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --target-root) TARGET_ROOT="$2"; shift 2 ;;
        --struct|-s) STRUCT_PATH="$2"; shift 2 ;;
        --simple-model-home) HOME_OVERRIDE="$2"; shift 2 ;;
        --json) JSON_OUT=1; shift ;;
        -h|--help|help) usage; exit 0 ;;
        --) shift; break ;;
        *) break ;;
    esac
done

[[ -n "$HOME_OVERRIDE" ]] && export SIMPLE_MODEL_HOME="$HOME_OVERRIDE"
SIMPLE_HOME="$(find_simple_model_home)"
TARGET_ROOT="$(cd "$TARGET_ROOT" 2>/dev/null && pwd || printf '%s' "$TARGET_ROOT")"
if [[ -z "$STRUCT_PATH" ]]; then
    if [[ -f "$TARGET_ROOT/struct.json" ]]; then
        STRUCT_PATH="$TARGET_ROOT/struct.json"
    else
        STRUCT_PATH="$SIMPLE_HOME/struct.json"
    fi
fi
[[ "$STRUCT_PATH" = /* ]] || STRUCT_PATH="$PWD/$STRUCT_PATH"

cmd="${1:-}"
[[ -n "$cmd" ]] || { usage; exit 64; }
shift || true

for arg in "$@"; do
    [[ "$arg" == "--json" ]] && JSON_OUT=1
done

case "$cmd" in
    doctor)
        doctor "$JSON_OUT"
        ;;
    commands)
        if [[ "$JSON_OUT" == "1" ]]; then
            jq . "$MANIFEST_FILE"
        else
            jq -r '.commands[] | "  " + .name + " - " + .description' "$MANIFEST_FILE"
        fi
        ;;
    validate)
        cd "$SIMPLE_HOME"
        ./bootstrap.sh --validate
        ./bootstrap.sh --check-all
        ./bootstrap.sh --lint --json | jq '.summary'
        ./bootstrap.sh --drift --json | jq '.summary'
        ;;
    full-check)
        cd "$SIMPLE_HOME"
        ./bootstrap.sh --validate
        ./bootstrap.sh --check-all
        ./bootstrap.sh --lint --json | jq '.summary'
        ./bootstrap.sh --drift --json | jq '.summary'
        for t in tests/test_*.sh; do bash "$t" || exit 1; done
        ;;
    ingest)
        repo="${1:-$TARGET_ROOT}"; out="${2:-$TARGET_ROOT/struct.ingested.json}"
        cd "$SIMPLE_HOME"
        generators/ingest_repo.sh --root "$repo" --output "$out" --json
        ;;
    audit)
        repo="${1:-$TARGET_ROOT}"
        cd "$SIMPLE_HOME"
        generators/adoption_audit.sh --root "$repo" --struct "$STRUCT_PATH" --json
        ;;
    interfaces)
        repo="${1:-$TARGET_ROOT}"
        cd "$SIMPLE_HOME"
        generators/interface_scan.sh --root "$repo" --struct "$STRUCT_PATH" --json
        ;;
    facts)
        repo="${1:-$TARGET_ROOT}"
        cd "$SIMPLE_HOME"
        generators/code_facts.sh --root "$repo" --struct "$STRUCT_PATH" --json
        ;;
    pr-gate)
        repo="${1:-$TARGET_ROOT}"; files="${2:-}"
        cd "$SIMPLE_HOME"
        if [[ -n "$files" ]]; then
            generators/pr_gate.sh --root "$repo" --struct "$STRUCT_PATH" --files "$files" --json
        else
            generators/pr_gate.sh --root "$repo" --struct "$STRUCT_PATH" --json
        fi
        ;;
    dashboard)
        out="${1:-$TARGET_ROOT/generated/dashboard.html}"
        cd "$SIMPLE_HOME"
        generators/dashboard.sh "$out"
        ;;
    resolve)
        cd "$SIMPLE_HOME"
        ./bootstrap.sh --struct "$STRUCT_PATH" --resolve --json
        ;;
    *)
        echo "[FAIL] unknown command: $cmd" >&2
        usage
        exit 64
        ;;
esac
