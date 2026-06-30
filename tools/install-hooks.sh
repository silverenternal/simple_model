#!/usr/bin/env bash
# install-hooks.sh — Copy hooks from .githooks/ into .git/hooks/
# Run once after cloning (or whenever hooks change) to enable them.

set -euo pipefail

# Locate the project root (the directory that contains .git/)
PROJECT_ROOT="$(git rev-parse --show-toplevel)"
HOOKS_SRC="${PROJECT_ROOT}/.githooks"
HOOKS_DST="${PROJECT_ROOT}/.git/hooks"

if [[ ! -d "${HOOKS_SRC}" ]]; then
    echo "error: hooks source directory not found at ${HOOKS_SRC}" >&2
    exit 1
fi

mkdir -p "${HOOKS_DST}"

shopt -s nullglob
copied=0
for hook in "${HOOKS_SRC}"/*; do
    name="$(basename "${hook}")"
    dest="${HOOKS_DST}/${name}"
    cp -f "${hook}" "${dest}"
    chmod +x "${dest}"
    echo "installed: ${name}"
    copied=$((copied + 1))
done
shopt -u nullglob

if [[ "${copied}" -eq 0 ]]; then
    echo "warning: no hooks found in ${HOOKS_SRC}" >&2
    exit 1
fi

echo "done — ${copied} hook(s) installed into ${HOOKS_DST}"