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
(cd plugins && zip -qr "../$out" simple-model-project-intelligence)
sum=$(sha256sum "$out" | awk '{print $1}')
jq -n --arg file "$out" --arg sha256 "$sum" --arg version "$VERSION" '{ok:true, file:$file, version:$version, sha256:$sha256}'
