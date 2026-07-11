#!/usr/bin/env bash
set -euo pipefail

ROOT="."
POLICY=""
OUT="generated/intelligence/runtime-observations.json"
MODE="plan"
JSON_OUT=0
TIMEOUT_SECONDS=10

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --policy) POLICY="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --execute) MODE="execute"; shift ;;
    --dry-run|--plan) MODE="plan"; shift ;;
    --timeout) TIMEOUT_SECONDS="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    -h|--help) echo "runtime_probe.sh --root <repo> [--policy .simple_model/probes.json] [--execute] [--json]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "[FAIL] missing jq" >&2; exit 2; }
[[ -d "$ROOT" ]] || { echo "[FAIL] root not found: $ROOT" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"
[[ -n "$POLICY" ]] || POLICY="$ROOT/.simple_model/probes.json"
mkdir -p "$(dirname "$OUT")"

if [[ ! -f "$POLICY" ]]; then
  report=$(jq -n --arg root "$ROOT" --arg policy "$POLICY" --arg mode "$MODE" '{
    schema_version:"1.0", ok:true, mode:$mode, root:$root, policy:$policy,
    summary:{probes:0, executed:0, observations:0, denied:0},
    probes:[], observations:[], denied:[],
    hints:["Create .simple_model/probes.json with allowed local discovery commands before using --execute."]
  }')
  printf '%s\n' "$report" > "$OUT"
  [[ "$JSON_OUT" == "1" ]] && printf '%s\n' "$report" || jq -r '"Runtime Probe probes=0 observations=0 output='"$OUT"'"' <<<"$report"
  exit 0
fi

jq empty "$POLICY"
if ! jq -e '.schema_version == "1.0" and (.probes|type=="array")' "$POLICY" >/dev/null; then
  echo "[FAIL] invalid probe policy: $POLICY" >&2
  exit 2
fi

if [[ "$MODE" != "execute" ]]; then
  report=$(jq -n --arg root "$ROOT" --arg policy "$POLICY" --arg mode "$MODE" --argjson probes "$(jq '.probes' "$POLICY")" '{
    schema_version:"1.0", ok:true, mode:$mode, root:$root, policy:$policy,
    summary:{probes:($probes|length), executed:0, observations:0, denied:0},
    probes:$probes, observations:[], denied:[],
    execution:{required_flag:"--execute", timeout_seconds:null}
  }')
  printf '%s\n' "$report" > "$OUT"
  [[ "$JSON_OUT" == "1" ]] && printf '%s\n' "$report" || jq -r '"Runtime Probe plan probes=" + (.summary.probes|tostring) + " output='"$OUT"'"' <<<"$report"
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
obs_file="$tmp/observations.jsonl"
exec_file="$tmp/executions.jsonl"
denied_file="$tmp/denied.jsonl"
: > "$obs_file"
: > "$exec_file"
: > "$denied_file"

export ROOT TIMEOUT_SECONDS obs_file exec_file denied_file
jq -c '.probes[]' "$POLICY" | while IFS= read -r probe; do
  enabled=$(jq -r '.enabled // true' <<<"$probe")
  [[ "$enabled" == "true" ]] || continue
  id=$(jq -r '.id' <<<"$probe")
  cmd=$(jq -r '.command' <<<"$probe")
  cwd=$(jq -r '.cwd // "."' <<<"$probe")
  parser=$(jq -r '.parser // "json-lines"' <<<"$probe")
  case "$cmd" in
    *";"*|*"&&"*|*"|"*|*">"*|*"<"*|*$'\n'*)
      jq -cn --arg id "$id" --arg command "$cmd" '{id:$id, command:$command, reason:"shell control operators are not allowed"}' >> "$denied_file"
      continue
      ;;
  esac
  if ! jq -e --arg cmd "$cmd" '(.allowed_commands // []) | index($cmd)' "$POLICY" >/dev/null; then
    jq -cn --arg id "$id" --arg command "$cmd" '{id:$id, command:$command, reason:"command is not listed in allowed_commands"}' >> "$denied_file"
    continue
  fi
  work="$ROOT/$cwd"
  [[ -d "$work" ]] || work="$ROOT"
  out="$tmp/$id.out"
  err="$tmp/$id.err"
  set +e
  if command -v timeout >/dev/null 2>&1; then
    (cd "$work" && env -i PATH="$PATH" HOME="${HOME:-}" PWD="$work" SIMPLE_MODEL_PROBE=1 timeout "$TIMEOUT_SECONDS" bash -lc "$cmd") >"$out" 2>"$err"
    rc=$?
  else
    (cd "$work" && env -i PATH="$PATH" HOME="${HOME:-}" PWD="$work" SIMPLE_MODEL_PROBE=1 bash -lc "$cmd") >"$out" 2>"$err"
    rc=$?
  fi
  set -e
  jq -cn --arg id "$id" --arg command "$cmd" --arg cwd "$cwd" --arg parser "$parser" --argjson exit_code "$rc" --rawfile stdout "$out" --rawfile stderr "$err" '{id:$id, command:$command, cwd:$cwd, parser:$parser, exit_code:$exit_code, ok:($exit_code==0), stdout:$stdout, stderr:$stderr}' >> "$exec_file"
  if [[ "$parser" == "json-lines" || "$parser" == "json" ]]; then
    python3 - "$id" "$out" >> "$obs_file" <<'PY'
import hashlib, json, sys
probe_id, path = sys.argv[1], sys.argv[2]
for line in open(path, encoding="utf-8", errors="ignore"):
    line = line.strip()
    if not line:
        continue
    try:
        obj = json.loads(line)
    except Exception:
        continue
    if not isinstance(obj, dict) or "kind" not in obj or "name" not in obj:
        continue
    obj.setdefault("source", probe_id)
    obj.setdefault("evidence", {})
    obj["hash"] = hashlib.sha256(json.dumps(obj, sort_keys=True).encode()).hexdigest()
    print(json.dumps(obj, separators=(",", ":"), sort_keys=True))
PY
  fi
done

executions=$(jq -s '.' "$exec_file")
observations=$(jq -s 'unique_by(.kind,.name,.path,.source)' "$obs_file")
denied=$(jq -s '.' "$denied_file")
report=$(jq -n \
  --arg root "$ROOT" \
  --arg policy "$POLICY" \
  --arg mode "$MODE" \
  --argjson probes "$(jq '.probes' "$POLICY")" \
  --argjson executions "$executions" \
  --argjson observations "$observations" \
  --argjson denied "$denied" '{
    schema_version:"1.0",
    ok:($denied|length == 0 and all($executions[]?; .ok)),
    mode:$mode,
    root:$root,
    policy:$policy,
    summary:{probes:($probes|length), executed:($executions|length), observations:($observations|length), denied:($denied|length)},
    probes:$probes,
    executions:$executions,
    observations:$observations,
    denied:$denied
  }')
printf '%s\n' "$report" > "$OUT"
[[ "$JSON_OUT" == "1" ]] && printf '%s\n' "$report" || jq -r '"Runtime Probe executed=" + (.summary.executed|tostring) + " observations=" + (.summary.observations|tostring) + " output='"$OUT"'"' <<<"$report"
jq -e '.ok == true' <<<"$report" >/dev/null
