#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{reads:[{name:"DATABASE_URL",path:"src/db.ts"}],schemas:[{name:"DATABASE_URL",path:"schema.json"}],defaults:[{name:"DATABASE_URL",path:"defaults.json"}],docs:[{name:"DATABASE_URL",path:"README.md"}],ci:[{name:"DATABASE_URL",path:"ci.yml"}],containers:[{name:"DATABASE_URL",path:"Dockerfile"}],deployments:[{name:"DATABASE_URL",path:"deploy.yml"}],secrets:[{name:"DATABASE_URL",provider:"vault",value:"do-not-record"}],flags:[{name:"old",branch_reachable:false,rollout_complete:true}]}' > "$tmp/input.json"
bash generators/config_surface_graph.sh --input "$tmp/input.json" --output "$tmp/graph.json" --json >/dev/null
jq -e '.summary.secret_value_captures==0 and all(.references[];(.value_recorded? != true)) and (.flags[0].removal_allowed==true)' "$tmp/graph.json" >/dev/null
jq -e '([.macros[]|select(.apply_capable)]|length)==3 and .policy.secret_value_captures==0' macros/packs/configuration-governance/pack.json >/dev/null
echo "  [OK] configuration graph secrets=0 flag reachability"
