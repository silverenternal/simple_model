#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
bash generators/meta_macro_execute.sh --input examples/meta-macro/input.json --output-dir "$tmp/pkg-a" --json >/dev/null
bash generators/meta_macro_execute.sh --input examples/meta-macro/input.json --output-dir "$tmp/pkg-b" --json >/dev/null
jq -e '.ok and .generated_package_completeness==1 and .self_policy_mutations==0 and .opaque_executable_blobs==0 and (.files|length)==5 and .promotion=="review_only_until_certified"' "$tmp/pkg-a/manifest.json" >/dev/null
cmp <(jq 'del(.package_hash)' "$tmp/pkg-a/manifest.json") <(jq 'del(.package_hash)' "$tmp/pkg-b/manifest.json")
for f in macro.json certification.template.json counterexample.template.json release-gate.template.json README.md; do test -s "$tmp/pkg-a/$f"; done
jq '.mutate_policy=true' examples/meta-macro/input.json > "$tmp/bad.json"
if bash generators/meta_macro_execute.sh --input "$tmp/bad.json" --output-dir "$tmp/bad" --json >/dev/null 2>&1; then exit 1; fi
jq -e '.self_policy_mutations==1 and .fail_closed==true' <(bash generators/meta_macro_execute.sh --input "$tmp/bad.json" --output-dir "$tmp/bad2" --json 2>/dev/null || true) >/dev/null
echo "  [OK] meta macro source package completeness/determinism/self-policy gate"
