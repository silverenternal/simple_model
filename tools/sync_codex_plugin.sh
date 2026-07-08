#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/codex/skills/simple-model-project-intelligence"
DST="$ROOT/plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence"
MODE="check"

usage() {
    cat <<'USAGE'
sync_codex_plugin.sh [--check|--sync]

Checks or refreshes the plugin-bundled skill from codex/skills.
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --check) MODE="check"; shift ;;
        --sync) MODE="sync"; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown arg: $1" >&2; usage; exit 64 ;;
    esac
done

[[ -d "$SRC" ]] || { echo "[FAIL] missing source skill: $SRC" >&2; exit 2; }
[[ -d "$(dirname "$DST")" ]] || { echo "[FAIL] missing plugin skills dir: $(dirname "$DST")" >&2; exit 2; }

if [[ "$MODE" == "sync" ]]; then
    rm -rf "$DST"
    cp -R "$SRC" "$DST"
    echo "[OK] synced plugin skill"
    exit 0
fi

tmp_src="$(mktemp)"
tmp_dst="$(mktemp)"
trap 'rm -f "$tmp_src" "$tmp_dst"' EXIT

(cd "$SRC" && find . -type f | sort | while read -r f; do sha256sum "$f"; done) > "$tmp_src"
(cd "$DST" && find . -type f | sort | while read -r f; do sha256sum "$f"; done) > "$tmp_dst"

if diff -u "$tmp_src" "$tmp_dst"; then
    echo "[OK] source skill and plugin skill are in sync"
else
    echo "[FAIL] source skill and plugin skill differ; run tools/sync_codex_plugin.sh --sync" >&2
    exit 1
fi
