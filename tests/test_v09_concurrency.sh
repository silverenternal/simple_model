#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
pass=0; fail=0; EXIT_CODE=0
check(){ local n="$1"; shift; if "$@" >/dev/null 2>&1; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n"; fail=$((fail+1)); EXIT_CODE=1; fi; }
check_exit(){ local n="$1" want="$2"; shift 2; set +e; "$@" >/dev/null 2>&1; rc=$?; set -e; if [[ "$rc" == "$want" ]]; then echo "  [OK]   $n"; pass=$((pass+1)); else echo "  [FAIL] $n (exit $rc, want $want)"; fail=$((fail+1)); EXIT_CODE=1; fi; }
cd "$ROOT_DIR"
echo "==============================================="
echo "  v0.9 concurrency tests"
echo "==============================================="

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

jq -n --arg tmp "$tmp" '{tasks:[
  {id:"a",command:"printf a",cwd:".",inputs:[],outputs:[($tmp + "/a")],deps:[],timeout:10,resource:"default",cache:false},
  {id:"b",command:"printf b",cwd:".",inputs:[],outputs:[($tmp + "/b")],deps:["a"],timeout:10,resource:"default",cache:false}
]}' > "$tmp/tasks.json"
check "worker pool runs portable bash tasks" bash generators/worker_pool.sh --tasks "$tmp/tasks.json" --output "$tmp/worker.json" --jobs 2 --json
check "worker output is stable" jq -e '.ok == true and .summary.tasks == 2 and (.results|map(.id)|join(",")) == "a,b"' "$tmp/worker.json"

check "parallel scheduler executes dependency stages" bash generators/parallel_scheduler.sh --tasks "$tmp/tasks.json" --output "$tmp/scheduler.json" --jobs 2 --json
check "scheduler records deterministic hash" jq -e '.ok == true and .summary.tasks == 2 and ((.scheduler_hash|length)>0) and (.summary.stages >= 2)' "$tmp/scheduler.json"

jq -n --arg tmp "$tmp" '{tasks:[
  {id:"x",command:"true",cwd:".",inputs:[],outputs:[($tmp + "/same")],deps:[],timeout:10},
  {id:"y",command:"true",cwd:".",inputs:[],outputs:[($tmp + "/same")],deps:[],timeout:10}
]}' > "$tmp/conflict.json"
check_exit "scheduler refuses write conflicts" 1 bash generators/parallel_scheduler.sh --tasks "$tmp/conflict.json" --output "$tmp/conflict-out.json" --jobs 2 --json
check "conflict report names write_set_conflict" jq -e '.ok == false and .error == "write_set_conflict" and (.conflicts|length)==1' "$tmp/conflict-out.json"

bash generators/optimization_plan.sh --root . --struct ./struct.json --output-dir "$tmp/opt" --json >/dev/null
check "macro simulation exposes concurrency metadata" bash generators/macro_simulate.sh --plan "$tmp/opt/plan.json" --output-dir "$tmp/opt" --jobs 2 --json
check "macro simulation remains simulation-only" jq -e '.ok == true and .concurrency.jobs == 2 and .concurrency.refused_apply == true and (.concurrency.partitions|length) >= 1' "$tmp/opt/simulation.json"

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
