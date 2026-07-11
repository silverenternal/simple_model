#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
root="$tmp/repo"; mkdir -p "$root"
printf 'input\n' > "$root/input.txt"
jq -n --arg root "$root" '{schema_version:"2.0",root:$root,backend:"local",command:{program:"bash",args:["-c","mkdir -p generated; printf done > generated/result.txt"]},tools:["bash"],env:{LC_ALL:"C"},network:false,write_paths:["generated"],resource_limits:{timeout_ms:2000,max_output_bytes:4096}}' > "$tmp/plan.json"
bash generators/hermetic_macro_runner.sh --plan "$tmp/plan.json" --output "$tmp/run-a.json" --json >/dev/null
jq -e '.ok and .status=="completed" and .checks.deterministic and .transaction.workspace_isolation and .rollback.success and (.writes|index("generated/result.txt")!=null)' "$tmp/run-a.json" >/dev/null
bash generators/hermetic_macro_runner.sh --plan "$tmp/plan.json" --output "$tmp/run-b.json" --json >/dev/null
jq -e '(.outputs.artifact_hash|length)==64 and .inputs.content_hash' "$tmp/run-b.json" >/dev/null
cmp <(jq 'del(.outputs.stdout,.outputs.stderr)' "$tmp/run-a.json") <(jq 'del(.outputs.stdout,.outputs.stderr)' "$tmp/run-b.json")
bash generators/hermetic_macro_runner.sh --plan "$tmp/plan.json" --output "$tmp/run-a.json" --resume --json >/dev/null
jq -e '.resumed==true and .status=="completed"' "$tmp/run-a.json" >/dev/null
jq -n --arg root "$root" '{schema_version:"2.0",root:$root,backend:"local",command:{program:"curl",args:["https://example.invalid"]},tools:["curl"],env:{},network:false,write_paths:[],resource_limits:{timeout_ms:1000,max_output_bytes:1024}}' > "$tmp/network.json"
if bash generators/hermetic_macro_runner.sh --plan "$tmp/network.json" --output "$tmp/network-report.json" --json >/dev/null 2>&1; then exit 1; fi
jq -e '.ok==false and .fail_closed==true and .rollback.success' "$tmp/network-report.json" >/dev/null
jq -n --arg root "$root" '{schema_version:"2.0",root:$root,backend:"local",command:{program:"bash",args:["-c","printf x > forbidden.txt"]},tools:["bash"],env:{},network:false,write_paths:["generated"],resource_limits:{timeout_ms:1000,max_output_bytes:1024}}' > "$tmp/write.json"
if bash generators/hermetic_macro_runner.sh --plan "$tmp/write.json" --output "$tmp/write-report.json" --json >/dev/null 2>&1; then exit 1; fi
jq -e '.ok==false and .error.code=="undeclared_write" and .rollback.success' "$tmp/write-report.json" >/dev/null
for backend in local container nix; do jq -e --arg b "$backend" '.backend==$b and .network==false and .fail_closed==true' "tools/sandbox_backends/$backend.json" >/dev/null; done
echo "  [OK] hermetic runner replay=1 rollback=1"
