#!/usr/bin/env bash
set -euo pipefail

CACHE="generated/.cache/simple_model/artifacts/index.json"
ROOT="."
COMMAND=""
INPUTS=""
RESULT=""
MODE="lookup"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --cache) CACHE="$2"; shift 2 ;;
    --root) ROOT="$2"; shift 2 ;;
    --command) COMMAND="$2"; shift 2 ;;
    --inputs) INPUTS="$2"; shift 2 ;;
    --result) RESULT="$2"; shift 2 ;;
    --lookup) MODE="lookup"; shift ;;
    --store) MODE="store"; shift ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
mkdir -p "$(dirname "$CACHE")"
[[ -f "$CACHE" ]] || printf '[]\n' > "$CACHE"
fingerprint_inputs=$(
  printf '%s\n' "$INPUTS" | tr ',' '\n' | awk 'NF' | sort -u | while IFS= read -r p; do
    [[ "$p" = /* ]] || p="$ROOT/$p"
    if [[ -f "$p" ]]; then
      h=$( (sha256sum "$p" 2>/dev/null || shasum -a 256 "$p") | awk '{print $1}' )
      jq -cn --arg path "${p#"$ROOT"/}" --arg hash "$h" '{path:$path,type:"file",hash:$hash}'
    elif [[ -d "$p" ]]; then
      h=$(cd "$ROOT" && find "${p#"$ROOT"/}" -type f | sort | while read -r f; do (sha256sum "$f" 2>/dev/null || shasum -a 256 "$f") | awk -v f="$f" '{print f ":" $1}'; done | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')
      jq -cn --arg path "${p#"$ROOT"/}" --arg hash "$h" '{path:$path,type:"dir",hash:$hash}'
    fi
  done | jq -s 'sort_by(.path)'
)
env_fp="$(bash --version | head -1) jq:$(jq --version)"
key=$(jq -n --arg command "$COMMAND" --arg env "$env_fp" --argjson inputs "$fingerprint_inputs" '{command:$command,env:$env,inputs:$inputs}' | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')
if [[ "$MODE" == "lookup" ]]; then
  hit_file="$(mktemp)"
  trap 'rm -f "$hit_file"' EXIT
  jq --arg key "$key" '[.[]|select(.key==$key)][0] // null' "$CACHE" > "$hit_file"
  jq -n --arg key "$key" --slurpfile hit "$hit_file" '{schema_version:"2.0", ok:true, mode:"lookup", key:$key, hit:($hit[0] != null), entry:$hit[0]}'
  exit 0
fi
[[ -f "$RESULT" ]] || { echo "[FAIL] --store requires --result" >&2; exit 2; }
result_hash=$( (sha256sum "$RESULT" 2>/dev/null || shasum -a 256 "$RESULT") | awk '{print $1}' )
entry_file="$(mktemp)"
trap 'rm -f "$entry_file"' EXIT
jq -n --arg key "$key" --arg command "$COMMAND" --arg env "$env_fp" --arg result_hash "$result_hash" --argjson inputs "$fingerprint_inputs" --slurpfile result "$RESULT" '{
  key:$key, command:$command, env:$env, inputs:$inputs, result_hash:$result_hash,
  result:($result[0] // {}), producer_version:"artifact-cache-v2", stored_at:"redacted",
  replay:{stable:true, requires_fresh_run:false}
}' > "$entry_file"
jq --arg key "$key" --slurpfile entry "$entry_file" '[.[]|select(.key != $key)] + [$entry[0]] | sort_by(.key)' "$CACHE" > "$CACHE.tmp"
mv "$CACHE.tmp" "$CACHE"
jq -n --arg key "$key" '{schema_version:"2.0", ok:true, mode:"store", key:$key, stored:true}'
