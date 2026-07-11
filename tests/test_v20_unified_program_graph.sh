#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

bash generators/unified_program_graph.sh --root examples/plugin-target-repo --struct examples/plugin-target-repo/struct.json --output "$tmp/graph-a.json" --partitions "$tmp/parts-a" --json >/dev/null
bash generators/unified_program_graph.sh --root examples/plugin-target-repo --struct examples/plugin-target-repo/struct.json --output "$tmp/graph-b.json" --partitions "$tmp/parts-b" --json >/dev/null

jq -e '.schema_version=="3.0" and .ok and (.graph_hash|length)==64 and .summary.nodes>0' "$tmp/graph-a.json"
jq -e 'all(.nodes[]; .id and .repository and .evidence.class and .evidence.freshness=="current" and (.evidence.invalidation_keys|type)=="array") and all(.edges[]; .evidence.provenance|length>0)' "$tmp/graph-a.json"
jq -e '.identity_policy.path_rename_stable and .identity_policy.unrelated_edit_stable and .identity_policy.collision_policy=="merge_same_logical_identity_with_provenance" and (.partitions|length)>0' "$tmp/graph-a.json"
cmp "$tmp/graph-a.json" "$tmp/graph-b.json"
bash generators/graph_partition_store.sh --dir "$tmp/parts-a" --output "$tmp/merged-a.json" --json >/dev/null
bash generators/graph_partition_store.sh --dir "$tmp/parts-b" --output "$tmp/merged-b.json" --json >/dev/null
cmp "$tmp/merged-a.json" "$tmp/merged-b.json"
jq -e --slurpfile source "$tmp/graph-a.json" '.summary.nodes==($source[0].summary.nodes) and .summary.edges==($source[0].summary.edges)' "$tmp/merged-a.json"
bash generators/unified_program_graph.sh --root examples/plugin-target-repo --struct examples/plugin-target-repo/struct.json --repository peer --output "$tmp/peer.json" --partitions "$tmp/parts-peer" --json >/dev/null
bash generators/unified_program_graph.sh --root examples/plugin-target-repo --struct examples/plugin-target-repo/struct.json --repository local --peer-graph "$tmp/peer.json" --output "$tmp/federated.json" --partitions "$tmp/parts-federated" --json >/dev/null
jq -e '.summary.repositories==2 and .summary.cross_repository_edges>0 and any(.edges[];.kind=="cross_repository_contract" and .evidence.class=="cross_repository")' "$tmp/federated.json"
cp -R examples/plugin-target-repo "$tmp/renamed-repo"
mv "$tmp/renamed-repo/src/api/server.ts" "$tmp/renamed-repo/src/api/renamed_server.ts"
bash generators/unified_program_graph.sh --root "$tmp/renamed-repo" --struct "$tmp/renamed-repo/struct.json" --repository plugin-target-repo --output "$tmp/renamed.json" --partitions "$tmp/parts-renamed" --json >/dev/null
jq -r '.nodes[]|select(.name=="startServer" and (.kind|startswith("symbol")))|.id' "$tmp/graph-a.json" | sort -u > "$tmp/ids-before"
jq -r '.nodes[]|select(.name=="startServer" and (.kind|startswith("symbol")))|.id' "$tmp/renamed.json" | sort -u > "$tmp/ids-after"
cmp "$tmp/ids-before" "$tmp/ids-after" || exit 1
echo "  [OK] unified program graph v3"
