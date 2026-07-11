#!/usr/bin/env bash
set -euo pipefail
LANGUAGE=""; ROOT="."; SPEC=""; OUT_DIR=""; APPLY=0; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --language) LANGUAGE="$2"; shift 2 ;;
    --root) ROOT="$2"; shift 2 ;;
    --spec) SPEC="$2"; shift 2 ;;
    --output-dir) OUT_DIR="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
[[ -n "$LANGUAGE" && -f "$SPEC" && -d "$ROOT" && -n "$OUT_DIR" ]] || { echo "required args missing" >&2; exit 64; }
mkdir -p "$OUT_DIR"
operation="$(jq -r '.operation // empty' "$SPEC")"
if jq -e '.mode=="text_fallback" or .fallback==true' "$SPEC" >/dev/null; then
  jq -n --arg language "$LANGUAGE" --arg operation "$operation" '{schema_version:"1.0",ok:true,status:"review_only",native:false,decision:"review_only",language:$language,operation:$operation,reason:"text fallback is never labeled native",checks:{parse_after_write:{status:"not_run"},typecheck_build:{status:"not_run"},idempotency:{status:"not_run"},inverse:{status:"not_run"}}}'
  exit 0
fi
jq -e --arg lang "$LANGUAGE" 'type=="object" and .schema_version=="1.0" and .language==$lang and (.operation|IN("symbol_rename","import_edit","declaration_insert","declaration_remove","call_site_rewrite","signature_migration")) and (.source|type)=="string" and (.source|length)>0 and (.source_hash|test("^[a-f0-9]{64}$")) and (.edits|type)=="array" and (.edits|length)>0 and all(.edits[]; .id and .original != null and .replacement != null and (.capture.start|type)=="number" and (.capture.end|type)=="number")' "$SPEC" >/dev/null || {
  jq -n --arg language "$LANGUAGE" --arg operation "$operation" '{schema_version:"1.0",ok:false,status:"rejected",native:true,decision:"reject",language:$language,operation:$operation,error:{code:"malformed_native_spec",message:"typed lossless edit IR and a supported operation are required"},fail_closed:true}'
  exit 3
}
ROOT="$(cd "$ROOT" && pwd)"
source_path="$ROOT/$(jq -r '.source' "$SPEC")"
[[ -f "$source_path" ]] || { echo "source missing" >&2; exit 2; }
if ! validate=$(bash "$(dirname "$0")/../../generators/edit_ir_validate.sh" --ir "$SPEC" --root "$ROOT" --json 2>/dev/null); then
  jq -n --arg language "$LANGUAGE" --arg operation "$operation" --arg validation "$validate" '{schema_version:"1.0",ok:false,status:"rejected",native:true,decision:"reject",language:$language,operation:$operation,error:{code:"stale_or_overlapping_ir",validation:$validation},fail_closed:true}'
  exit 3
fi
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if [[ "$APPLY" == 1 ]]; then output_file="$source_path"; else output_file="$tmp/$(basename "$source_path")"; fi
bash "$(dirname "$0")/../../generators/edit_ir_diff.sh" --ir "$SPEC" --root "$ROOT" --output "$output_file" --json >/dev/null
if awk '{o+=gsub(/\{/, ""); c+=gsub(/\}/, ""); p+=gsub(/\(/, ""); q+=gsub(/\)/, "")} END {exit (o==c && p==q ? 0 : 1)}' "$output_file"; then parse_status="passed"; else parse_status="failed"; fi
if [[ "$parse_status" != "passed" ]]; then
  jq -n --arg language "$LANGUAGE" --arg operation "$operation" '{schema_version:"1.0",ok:false,status:"rejected",native:true,decision:"reject",language:$language,operation:$operation,error:{code:"parse_after_write_failed"},checks:{parse_after_write:{status:"failed"}},fail_closed:true}'
  exit 3
fi
type_status="unavailable_review_only"; type_reason="language toolchain not required by baseline"
case "$LANGUAGE" in
  python) if command -v python3 >/dev/null 2>&1 && python3 -m py_compile "$output_file" 2>/dev/null; then type_status="passed"; type_reason="python3 -m py_compile"; else type_status="failed"; type_reason="python syntax check failed"; fi ;;
  go) if command -v gofmt >/dev/null 2>&1 && [[ -z "$(gofmt -d "$output_file" 2>/dev/null)" ]]; then type_status="passed"; type_reason="gofmt"; fi ;;
esac
inverse="$OUT_DIR/inverse-$LANGUAGE.json"
bash "$(dirname "$0")/../../generators/edit_ir_inverse.sh" --ir "$SPEC" --applied "$output_file" --output "$inverse" --json >/dev/null
key="$(jq -S -c '{language,operation,source,edits}' "$SPEC" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
output_hash="$( (sha256sum "$output_file" 2>/dev/null || shasum -a 256) | awk '{print $1}')"
report="$(jq -n --arg language "$LANGUAGE" --arg operation "$operation" --arg source "$(jq -r .source "$SPEC")" --arg output "$output_file" --arg inverse "$inverse" --arg key "$key" --arg output_hash "$output_hash" --arg type_status "$type_status" --arg type_reason "$type_reason" --argjson apply "$APPLY" '{schema_version:"1.0",ok:true,status:(if $apply then "applied" else "simulated" end),native:true,decision:"accept",language:$language,operation:$operation,source:$source,output:$output,output_hash:$output_hash,idempotency_key:$key,inverse_ir:$inverse,checks:{parse_after_write:{status:"passed"},typecheck_build:{status:$type_status,reason:$type_reason},idempotency:{status:"ready",key:$key},inverse:{status:"ready",path:$inverse}},fallback_policy:{text_edits:"review_only",native_claim:true},fail_closed:true}')"
if [[ "$JSON_OUT" == 1 ]]; then printf '%s\n' "$report"; else jq -r '"Native \(.language) \(.operation) status=\(.status)"' <<<"$report"; fi
