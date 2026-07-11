#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -e '.entries|length==60 and ([.[].language]|unique|length)==6 and ([.[].framework]|unique|length)==12 and ([.[].monorepo|select(.)]|length)==10 and ([.[].dynamic_code|select(.)]|length)==15 and ([.[].partition]|unique|length)==2' benchmarks/external-corpus/manifest.json >/dev/null
bash generators/corpus_materialize.sh --manifest benchmarks/external-corpus/manifest.json --output-dir "$tmp/materialized" --json >/dev/null
jq -e '.entries==60 and .materialized_metadata_only and (.content_hash|length)==64' "$tmp/materialized/manifest.json" >/dev/null
bash generators/corpus_license_check.sh --manifest benchmarks/external-corpus/manifest.json --output "$tmp/license.json" --json >/dev/null
jq -e '.ok and .redistribution_violations==0 and .private_source_leaks==0' "$tmp/license.json" >/dev/null
echo "  [OK] external corpus repositories=60 languages=6 frameworks=12 held_out locked"

