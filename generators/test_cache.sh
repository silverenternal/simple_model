#!/usr/bin/env bash
set -euo pipefail

CACHE="generated/.cache/simple_model/test-cache.json"
COMMAND=""
ROOT="."
MODE="lookup"
RESULT=""
INPUTS=""
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cache) CACHE="$2"; shift 2 ;;
    --command) COMMAND="$2"; shift 2 ;;
    --root) ROOT="$2"; shift 2 ;;
    --result) RESULT="$2"; shift 2 ;;
    --inputs) INPUTS="$2"; shift 2 ;;
    --lookup) MODE="lookup"; shift ;;
    --store) MODE="store"; shift ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

mkdir -p "$(dirname "$CACHE")"
[[ -f "$CACHE" ]] || printf '[]\n' > "$CACHE"
ROOT="$(cd "$ROOT" && pwd)"
script=$(awk '{print $2}' <<<"$COMMAND")
[[ -f "$script" ]] || script="$(awk '{print $1}' <<<"$COMMAND")"
script_hash=""
[[ -f "$script" ]] && script_hash=$( (sha256sum "$script" 2>/dev/null || shasum -a 256 "$script") | awk '{print $1}' )
env_fp="$(bash --version | head -1) jq:$(jq --version)"
input_hashes=$(
  {
    [[ -n "$INPUTS" ]] && printf '%s\n' "$INPUTS" | tr ',' '\n'
    [[ -f "$script" ]] && printf '%s\n' "$script"
    printf '%s\n' struct.json todo.json specs codex/skills plugins tools generators
  } | awk 'NF' | sort -u | while IFS= read -r p; do
    [[ "$p" = /* ]] || p="$ROOT/$p"
    if [[ -f "$p" ]]; then
      h=$( (sha256sum "$p" 2>/dev/null || shasum -a 256 "$p") | awk '{print $1}' )
      jq -cn --arg path "${p#"$ROOT"/}" --arg hash "$h" '{path:$path,hash:$hash,type:"file"}'
    elif [[ -d "$p" ]]; then
      h=$(cd "$ROOT" && find "${p#"$ROOT"/}" -type f 2>/dev/null | sort | while read -r f; do
        (sha256sum "$f" 2>/dev/null || shasum -a 256 "$f") | awk -v file="$f" '{print file ":" $1}'
      done | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')
      jq -cn --arg path "${p#"$ROOT"/}" --arg hash "$h" '{path:$path,hash:$hash,type:"dir"}'
    fi
  done | jq -s 'sort_by(.path)'
)
key=$(jq -n --arg command "$COMMAND" --arg script_hash "$script_hash" --arg env "$env_fp" --arg root "$ROOT" --argjson inputs "$input_hashes" '{command:$command,script_hash:$script_hash,env:$env,root:$root,inputs:$inputs}' | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')

if [[ "$MODE" == "lookup" ]]; then
  hit=$(jq --arg key "$key" '[.[]|select(.key==$key)][0] // null' "$CACHE")
  jq -n --arg key "$key" --argjson hit "$hit" '{schema_version:"1.0", ok:true, mode:"lookup", key:$key, hit:($hit != null), entry:$hit}'
  exit 0
fi

[[ -n "$RESULT" && -f "$RESULT" ]] || { echo "[FAIL] --store requires --result file" >&2; exit 2; }
entry=$(jq -n --arg key "$key" --arg command "$COMMAND" --arg script_hash "$script_hash" --arg env "$env_fp" --argjson inputs "$input_hashes" --slurpfile result "$RESULT" '{key:$key, command:$command, script_hash:$script_hash, env:$env, inputs:$inputs, result:($result[0] // {}), stdout_digest:(($result[0].stdout_digest // "")|tostring), stderr_digest:(($result[0].stderr_digest // "")|tostring), duration_seconds:($result[0].duration_seconds // 0), stored_at:"redacted"}')
jq --arg key "$key" --argjson entry "$entry" '[.[]|select(.key != $key)] + [$entry] | sort_by(.key)' "$CACHE" > "$CACHE.tmp"
mv "$CACHE.tmp" "$CACHE"
jq -n --arg key "$key" '{schema_version:"1.0", ok:true, mode:"store", key:$key, stored:true}'
