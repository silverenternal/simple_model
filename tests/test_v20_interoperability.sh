#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' | bash tools/simple_model_mcp_v2.sh > "$tmp/list.json"
jq -e '(.result.tools|length)==6 and ([.result.tools[].name]|sort)==["adapter_facts","approval_status","macro_simulate","mql_plan","project_graph","proof_bundle"]' "$tmp/list.json" >/dev/null
printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"macro_simulate","arguments":{"macro":"fixture"}}}' | bash tools/simple_model_mcp_v2.sh > "$tmp/a.json"
printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"macro_simulate","arguments":{"macro":"fixture"}}}' | bash tools/simple_model_mcp_v2.sh > "$tmp/b.json"
diff -u <(jq -S '.result' "$tmp/a.json") <(jq -S '.result' "$tmp/b.json")
for d in openrewrite codeql semgrep ast-grep; do jq -e '.capabilities|index("provenance")' "adapters/$d/adapter.json" >/dev/null; done
jq -e '.result.result? // .result | .decision.write==false and .proof.approval_required' "$tmp/a.json" >/dev/null
echo "  [OK] interoperability MCP tools=6 adapters=4 decision-drift=0"
