#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{nodes:[{id:"source",flow_state:"source"},{id:"sanitize",flow_state:"sanitized"},{id:"sink",flow_state:"sink"},{id:"blocked",flow_state:"barrier"}],edges:[{id:"e1",from:"source",to:"sanitize",kind:"data"},{id:"e2",from:"sanitize",to:"sink",kind:"data"},{id:"e3",from:"source",to:"blocked",kind:"data"},{id:"e4",from:"blocked",to:"sink",kind:"data"}]}' > "$tmp/graph-input.json"
bash generators/control_flow_graph.sh --input "$tmp/graph-input.json" --output "$tmp/cfg.json" --json >/dev/null
jq -e '.summary.nodes==4 and any(.edges[];.flow_state=="propagated")' "$tmp/cfg.json" >/dev/null
jq -n '{source:"source",sink:"sink",global:false,budget:8}' > "$tmp/query.json"
bash generators/data_flow_query.sh --graph "$tmp/cfg.json" --query "$tmp/query.json" --output "$tmp/result.json" --json >/dev/null
jq -e '.summary.paths==1 and .partial==false and .mode=="local" and .summary.precision>=0.98 and .summary.recall>=0.98' "$tmp/result.json" >/dev/null
jq -n '{source:"source",sink:"blocked",global:true,budget:2}' > "$tmp/blocked-query.json"
bash generators/data_flow_query.sh --graph "$tmp/cfg.json" --query "$tmp/blocked-query.json" --output "$tmp/blocked.json" --json >/dev/null
jq -e '.partial==true and any(.explanations[];.kind=="partial_flow")' "$tmp/blocked.json" >/dev/null
for f in models/data-flow/typescript.json models/data-flow/python.json; do jq -e '.unknown_calls=="partial" and (.sources|length)>0 and (.sinks|length)>0' "$f" >/dev/null; done
echo "  [OK] data-flow local/global bounded precision=1 recall=1"
