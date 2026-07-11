#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION=""

usage() {
    cat <<'USAGE'
package_codex_plugin.sh --version <version>

Validates and packages plugins/simple-model-project-intelligence into dist/.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 64 ;;
    esac
done

[[ -n "$VERSION" ]] || { usage; exit 64; }

cd "$ROOT"
bash tools/sync_codex_plugin.sh --check >/dev/null
jq empty .agents/plugins/marketplace.json
jq -e --arg v "$VERSION" '.version == $v' plugins/simple-model-project-intelligence/.codex-plugin/plugin.json >/dev/null
jq empty plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/references/command-manifest.json
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh commands --json >/dev/null

mkdir -p dist
out="dist/simple-model-project-intelligence-plugin-${VERSION}.zip"
rm -f "$out"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/simple-model-project-intelligence"
cp -R plugins/simple-model-project-intelligence/. "$tmp/simple-model-project-intelligence/"

hash_file() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

self_check_hash=""
if [[ -f generated/plugin-self-audit/latest.json ]]; then
    self_check_hash="$(hash_file generated/plugin-self-audit/latest.json)"
fi
dynamic_scorecard='{}'
if [[ -f generated/benchmarks/scorecard.json ]]; then
    dynamic_scorecard=$(jq '{dynamic_precision:(.metrics.dynamic_precision // null), dynamic_recall:(.metrics.dynamic_recall // null), dynamic_observation_coverage:(.metrics.dynamic_observation_coverage // null), dynamic_unsafe_detection_rate:(.metrics.dynamic_unsafe_detection_rate // null), thresholds:(.thresholds // {})}' generated/benchmarks/scorecard.json)
fi
performance_scorecard='{}'
if [[ -f generated/performance/scorecard.json ]]; then
    performance_scorecard=$(jq '{ok, summary, budgets}' generated/performance/scorecard.json)
fi
production_scorecard='{}'
if [[ -f generated/benchmarks/production-scorecard.json ]]; then
    production_scorecard=$(jq '{ok, metrics, thresholds}' generated/benchmarks/production-scorecard.json)
fi
release_slo='{}'
if [[ -f generated/releases/v1.0-readiness.json ]]; then
    release_slo=$(jq '{ok, checks, v1_readiness}' generated/releases/v1.0-readiness.json)
fi
release_slo_v11='{}'
if [[ -f generated/releases/v1.1-readiness.json ]]; then
    release_slo_v11=$(jq '{ok, checks, v11_readiness}' generated/releases/v1.1-readiness.json)
fi
release_slo_v12='{}'
if [[ -f generated/releases/v1.2-macro-readiness.json ]]; then
    release_slo_v12=$(jq '{ok, checks, v12_macro_readiness}' generated/releases/v1.2-macro-readiness.json)
fi

files_json=$(
    cd "$tmp/simple-model-project-intelligence"
    find . -type f ! -name release-manifest.json | sort | while read -r f; do
        h=$(hash_file "$f")
        jq -cn --arg path "${f#./}" --arg sha256 "$h" '{path:$path, sha256:$sha256}'
    done | jq -s '.'
)

jq -n \
  --arg plugin "simple-model-project-intelligence" \
  --arg version "$VERSION" \
  --arg git_commit "$(git rev-parse HEAD 2>/dev/null || echo unknown)" \
  --arg created_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg self_check_hash "$self_check_hash" \
  --argjson dynamic_scorecard "$dynamic_scorecard" \
  --argjson performance_scorecard "$performance_scorecard" \
  --argjson production_scorecard "$production_scorecard" \
  --argjson release_slo "$release_slo" \
  --argjson release_slo_v11 "$release_slo_v11" \
  --argjson release_slo_v12 "$release_slo_v12" \
  --argjson files "$files_json" \
  '{schema_version:"1.0", plugin:$plugin, version:$version, git_commit:$git_commit, created_at:$created_at, self_check:{hash:$self_check_hash}, dynamic_scorecard:$dynamic_scorecard, performance_scorecard:$performance_scorecard, production_scorecard:$production_scorecard, release_slo:$release_slo, release_slo_v11:$release_slo_v11, release_slo_v12:$release_slo_v12, scheduler_determinism_hash:($performance_scorecard.summary.deterministic_hash // ""), files:$files}' \
  > "$tmp/simple-model-project-intelligence/release-manifest.json"

(cd "$tmp" && zip -qr "$ROOT/$out" simple-model-project-intelligence)
sum=$(hash_file "$out")
manifest_sum=$(hash_file "$tmp/simple-model-project-intelligence/release-manifest.json")
zipinfo -1 "$out" > "$tmp/zip-list.txt"
grep -q '^simple-model-project-intelligence/release-manifest.json$' "$tmp/zip-list.txt"
jq -n --arg file "$out" --arg sha256 "$sum" --arg manifest_sha256 "$manifest_sum" --arg version "$VERSION" '{ok:true, file:$file, version:$version, sha256:$sha256, manifest:"release-manifest.json", manifest_sha256:$manifest_sha256}'
