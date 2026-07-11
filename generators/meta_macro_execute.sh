#!/usr/bin/env bash
set -euo pipefail
INPUT=""; OUT_DIR="generated/macros/meta-generated"; JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in --input|-i) INPUT="$2"; shift 2 ;; --output-dir) OUT_DIR="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$INPUT" ]] || { echo "--input is required" >&2; exit 64; }
mkdir -p "$OUT_DIR"
jq -e 'type=="object" and .schema_version=="2.0" and (.family_id|test("^[a-z][a-z0-9._-]+$")) and (.parameters|type)=="object" and (.evidence|type)=="object" and ((.mutate_policy//false)==false)' "$INPUT" >/dev/null || { jq -n '{schema_version:"1.0",ok:false,error:{code:"self_policy_mutation_or_malformed_input"},self_policy_mutations:1,fail_closed:true}'; exit 3; }
family="$(jq -r '.family_id' "$INPUT")"; version="$(jq -r '.parameters.version // "0.1.0"' "$INPUT")"
jq -n --arg family "$family" --arg version "$version" '{schema_version:"1.0",id:$family,version:$version,status:"review_only",apply_capable:false,trust_policy:"inherited_from_certification",source_package:true}' > "$OUT_DIR/macro.json"
jq -n --arg family "$family" '{schema_version:"1.0",macro_id:$family,required_fixture_kinds:["positive","negative","adversarial","partial_parse","dirty_worktree","rollback"],certificate_required:true,apply_allowed:false}' > "$OUT_DIR/certification.template.json"
jq -n --arg family "$family" '{schema_version:"1.0",macro_id:$family,proof_obligation:"generated-regression",input:{},expected:{},observed:{},regression_fixture:true}' > "$OUT_DIR/counterexample.template.json"
jq -n --arg family "$family" '{schema_version:"1.0",macro_id:$family,required_checks:["validate","check-all","lint","drift","tests"],promotion_requires_certificate:true}' > "$OUT_DIR/release-gate.template.json"
printf '# Generated macro family: %s\n\nThis is a reviewable source package. Fill proof evidence, certify fixtures, and pass the release gate before apply mode.\n' "$family" > "$OUT_DIR/README.md"
files=(macro.json certification.template.json counterexample.template.json release-gate.template.json README.md)
file_hash="$(for f in "${files[@]}"; do printf '%s\n' "$f"; (sha256sum "$OUT_DIR/$f" 2>/dev/null || shasum -a 256 "$OUT_DIR/$f"); done | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
jq -n --arg family "$family" --arg hash "$file_hash" --argjson files "$(printf '%s\n' "${files[@]}"|jq -R .|jq -s .)" '{schema_version:"1.0",ok:true,family_id:$family,files:$files,package_hash:$hash,generated_package_completeness:1.0,self_policy_mutations:0,opaque_executable_blobs:0,deterministic:true,promotion:"review_only_until_certified"}' > "$OUT_DIR/manifest.json"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT_DIR/manifest.json"; else jq -r '"Meta macro package \(.family_id) files=\(.files|length)"' "$OUT_DIR/manifest.json"; fi
