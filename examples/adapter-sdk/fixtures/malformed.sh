#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in --manifest) exec "$(dirname "$0")/../adapters/parser-reference.sh" --manifest ;; --request) printf '{"protocol":"adapter-protocol-v1"}\n' ;; *) exit 64 ;; esac
