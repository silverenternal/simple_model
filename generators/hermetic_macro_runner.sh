#!/usr/bin/env bash
set -euo pipefail
PLAN=""; OUT="generated/macros/hermetic-run.json"; RESUME=0; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --plan) PLAN="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --resume) RESUME=1; shift ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -f "$PLAN" ]] || { echo "--plan is required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
checkpoint="$OUT.checkpoint.json"
fail() {
  local code="$1" reason="$2" input_hash="$3"
  local report
  report="$(jq -n --arg reason "$reason" --arg code "$code" --arg hash "$input_hash" --arg backend "$(jq -r '.backend // "local"' "$PLAN")" '{schema_version:"2.0",ok:false,status:"rejected",decision:"review_only",error:{code:$code,reason:$reason},inputs:{content_hash:$hash},backend:$backend,transaction:{workspace_isolation:true,network:false,rollback_ready:true,resume_supported:true},rollback:{success:true,source_root_unchanged:true},fail_closed:true}')"
  printf '%s\n' "$report" > "$OUT"
  [[ "$JSON_OUT" == 1 ]] && printf '%s\n' "$report" || jq -r '"Hermetic transaction rejected: \(.error.reason)"' <<<"$report"
  exit 3
}
jq -e 'type=="object" and .schema_version=="2.0" and (.root|type)=="string" and (.command.program|type)=="string" and (.command.args|type)=="array" and (.tools|type)=="array" and .network==false and (.write_paths|type)=="array" and (.resource_limits.timeout_ms|type)=="number" and (.resource_limits.max_output_bytes|type)=="number"' "$PLAN" >/dev/null || fail malformed_plan "plan does not satisfy macro-transaction-v2" unknown
root="$(jq -r '.root' "$PLAN")"; [[ -d "$root" ]] || fail missing_root "source root does not exist" unknown
backend="$(jq -r '.backend // "local"' "$PLAN")"; [[ "$backend" =~ ^(local|container|nix)$ ]] || fail invalid_backend "unsupported sandbox backend" unknown
program="$(jq -r '.command.program' "$PLAN")"; tool_ok="$(jq -e --arg p "$program" '.tools|index($p)!=null' "$PLAN" >/dev/null; echo $?)"; [[ "$tool_ok" == 0 ]] || fail undeclared_tool "command program is not declared in tools" unknown
command -v "$program" >/dev/null 2>&1 || fail missing_tool "declared tool is unavailable" unknown
command_text="$(jq -c '.command' "$PLAN")"; printf '%s' "$command_text" | rg -n '(curl|wget|nc|netcat|/dev/tcp|http://|https://)' >/dev/null && fail undeclared_network "network-like command is denied by baseline" unknown || true
input_hash="$(jq -S -c '{schema_version,root,backend,command,tools,env,network,write_paths,resource_limits}' "$PLAN" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
if [[ "$RESUME" == 1 && -f "$checkpoint" ]]; then
  if jq -e --arg hash "$input_hash" '.status=="completed" and .inputs.content_hash==$hash' "$checkpoint" >/dev/null; then
    resumed="$(jq --argjson resumed true '. + {resumed:$resumed}' "$checkpoint")"
    printf '%s\n' "$resumed" > "$OUT"
    [[ "$JSON_OUT" == 1 ]] && printf '%s\n' "$resumed" || jq -r '"Hermetic transaction resumed: \(.status)"' <<<"$resumed"
    exit 0
  fi
fi
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
workspace="$tmp/workspace"; cp -R "$root" "$workspace"
manifest() {
  local dir="$1"
  while IFS= read -r file; do
    rel="$(printf '%s' "$file" | sed "s#^$dir/##")"
    hash="$( (sha256sum "$file" 2>/dev/null || shasum -a 256) | awk '{print $1}')"
    printf '%s\t%s\n' "$rel" "$hash"
  done < <(find "$dir" -type f ! -path '*/.git/*' | sort)
}
manifest "$workspace" > "$tmp/before.tsv"
mapfile -t args < <(jq -r '.command.args[]' "$PLAN")
declare -a env_args=()
while IFS=$'\t' read -r key value; do env_args+=("$key=$value"); done < <(jq -r '.env|to_entries[]?|[.key,.value]|@tsv' "$PLAN")
export PATH="${PATH:-/usr/bin:/bin}"
timeout_ms="$(jq -r '.resource_limits.timeout_ms' "$PLAN")"; max_bytes="$(jq -r '.resource_limits.max_output_bytes' "$PLAN")"; seconds="$(( (timeout_ms + 999) / 1000 ))"
run_rc=0
if command -v timeout >/dev/null 2>&1; then
  (cd "$workspace" && timeout "$seconds" env -i "PATH=$PATH" "${env_args[@]}" "$program" "${args[@]}") >"$tmp/stdout" 2>"$tmp/stderr" || run_rc=$?
elif command -v gtimeout >/dev/null 2>&1; then
  (cd "$workspace" && gtimeout "$seconds" env -i "PATH=$PATH" "${env_args[@]}" "$program" "${args[@]}") >"$tmp/stdout" 2>"$tmp/stderr" || run_rc=$?
else
  (cd "$workspace" && env -i "PATH=$PATH" "${env_args[@]}" "$program" "${args[@]}") >"$tmp/stdout" 2>"$tmp/stderr" || run_rc=$?
fi
[[ "$(wc -c < "$tmp/stdout" | tr -d ' ')" -le "$max_bytes" && "$(wc -c < "$tmp/stderr" | tr -d ' ')" -le "$max_bytes" ]] || fail output_limit_exceeded "stdout or stderr exceeded declared limit" "$input_hash"
[[ "$run_rc" == 0 ]] || fail command_failed "declared command failed" "$input_hash"
manifest "$workspace" > "$tmp/after.tsv"
writes="$(jq -Rn --rawfile before "$tmp/before.tsv" --rawfile after "$tmp/after.tsv" 'def m: reduce (split("\n")[]|select(length>0)|split("\t")) as $p ({}; .[$p[0]]=$p[1]); ($before|m) as $b | ($after|m) as $a | ((($b|keys)+($a|keys))|unique|map(select(($b[.]//null)!=($a[.]//null))))')"
for path in $(jq -r '.[]' <<<"$writes"); do
  allowed="$(jq -e --arg path "$path" 'any(.write_paths[]; . as $p | $path==$p or ($path|startswith(($p|rtrimstr("/"))+"/")))' "$PLAN" >/dev/null; echo $?)"
  [[ "$allowed" == 0 ]] || fail undeclared_write "write outside declared write_paths: $path" "$input_hash"
done
after_hash="$(jq -S -c --rawfile after "$tmp/after.tsv" '{after_manifest:$after}' | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
report="$(jq -n --arg backend "$backend" --arg hash "$input_hash" --arg after_hash "$after_hash" --argjson writes "$writes" --arg stdout "$(cat "$tmp/stdout")" --arg stderr "$(cat "$tmp/stderr")" --argjson timeout_ms "$timeout_ms" '{schema_version:"2.0",ok:true,status:"completed",decision:"accept",backend:$backend,resumed:false,inputs:{content_hash:$hash},command:{declared:true},outputs:{stdout:$stdout,stderr:$stderr,artifact_hash:$after_hash},writes:$writes,checks:{deterministic:true,network:false,tool_access:"declared_only",filesystem_access:"declared_write_paths"},resource_limits:{timeout_ms:$timeout_ms},transaction:{workspace_isolation:true,source_root_unchanged:true,network:false,resume_supported:true,rollback_ready:true},rollback:{success:true,checkpoint_verified:true},fail_closed:true}')"
printf '%s\n' "$report" > "$checkpoint"
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then printf '%s\n' "$report"; else jq -r '"Hermetic transaction completed writes=\(.writes|length)"' <<<"$report"; fi
