#!/usr/bin/env bash
set -euo pipefail
case "${1:-}" in --manifest) exec "$(dirname "$0")/../adapters/parser-reference.sh" --manifest ;; --request) jq '{protocol:"adapter-protocol-v1",request_id:.request_id,adapter:{id:"parser-reference",version:"1.0.0"}}' "$2" ;; *) exit 64 ;; esac
