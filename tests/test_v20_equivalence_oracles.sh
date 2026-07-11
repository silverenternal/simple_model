#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '{schema_version:"1.0",mode:"exact",before:{status:200,body:{ok:true}},after:{status:200,body:{ok:true}},unit_tests_passed:true}' > "$tmp/exact.json"
bash generators/equivalence_oracle.sh --contract "$tmp/exact.json" --output "$tmp/exact-report.json" --json >/dev/null
jq -e '.equivalent and .unit_tests_passed and .diffs==[]' "$tmp/exact-report.json" >/dev/null
jq -n '{schema_version:"1.0",mode:"exact",before:{status:200},after:{status:500},unit_tests_passed:true}' > "$tmp/fail.json"
bash generators/equivalence_oracle.sh --contract "$tmp/fail.json" --output "$tmp/fail-report.json" --json >/dev/null
jq -e '.equivalent==false and .unit_tests_passed and (.minimized_failure.paths|length)>0 and (.graph_paths|length)>0' "$tmp/fail-report.json" >/dev/null
jq -n '{schema_version:"1.0",mode:"normalized",before:{timestamp:"2026-01-01T00:00:00Z",value:1},after:{timestamp:"2026-01-02T00:00:00Z",value:1},normalizers:[{path:"timestamp",type:"timestamp"}]}' > "$tmp/norm.json"
bash generators/equivalence_oracle.sh --contract "$tmp/norm.json" --output "$tmp/norm-report.json" --json >/dev/null
jq -e '.equivalent and .metrics.untyped_ignored_fields==0' "$tmp/norm-report.json" >/dev/null
jq -n '{schema_version:"1.0",mode:"normalized",before:{timestamp:"a"},after:{timestamp:"b"},normalizers:[{path:"timestamp"}]}' > "$tmp/untyped.json"
if bash generators/equivalence_oracle.sh --contract "$tmp/untyped.json" --output "$tmp/untyped-report.json" --json >/dev/null 2>&1; then exit 1; fi
jq -e '.ok==false and .error.code=="untyped_ignored_field"' "$tmp/untyped-report.json" >/dev/null
jq -n '{schema_version:"1.0",mode:"observational",before:{status:200,debug:"a"},after:{status:200,debug:"b"},observe_paths:["status"]}' > "$tmp/obs.json"
bash generators/equivalence_oracle.sh --contract "$tmp/obs.json" --output "$tmp/obs-report.json" --json >/dev/null
jq -e '.equivalent' "$tmp/obs-report.json" >/dev/null
jq -n '{schema_version:"1.0",mode:"breaking",before:{field:1},after:{field:2}}' > "$tmp/breaking.json"
bash generators/equivalence_oracle.sh --contract "$tmp/breaking.json" --output "$tmp/breaking-report.json" --json >/dev/null
jq -e '.equivalent and .mode=="breaking"' "$tmp/breaking-report.json" >/dev/null
jq -n '{mode:"exact",normalizers:[],examples:[{before:{x:1},after:{x:1}}]}' > "$tmp/miner-input.json"
bash generators/golden_contract_miner.sh --input "$tmp/miner-input.json" --output "$tmp/miner.json" --json >/dev/null
jq -e '.ok and .evidence.examples==1 and .before.x==1' "$tmp/miner.json" >/dev/null
echo "  [OK] equivalence oracle typed normalization/contract failures"
