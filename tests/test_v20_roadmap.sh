#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

pass=0
fail=0
check() {
  local name="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    printf '  [OK]   %s\n' "$name"
    pass=$((pass + 1))
  else
    printf '  [FAIL] %s\n' "$name"
    fail=$((fail + 1))
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

check "roadmap identity and size" jq -e '
  .version == "2.0-executable-macro-wisdom-roadmap"
  and .status == "planned"
  and (.waves|length) == 7
  and (.todos|length) >= 45
' todo.json

check "all roadmap items are concrete" jq -e '
all(.todos[];
    (.status == "pending" or .status == "done")
    and (.goal|length) > 40
    and (.deliverables|length) >= 4
    and (.acceptance|length) >= 4
    and (.dependencies|type) == "array"
    and (.metrics|type) == "object"
    and (.metrics|length) >= 2)
' todo.json

check "roadmap ids are unique" jq -e '
  ([.todos[].id]|length) == ([.todos[].id]|unique|length)
' todo.json

check "all dependencies exist" jq -e '
  [.todos[].id] as $ids
  | all(.todos[]; all(.dependencies[]?; ($ids|index(.)) != null))
' todo.json

jq -r '.todos[] | .dependencies[]? as $dep | "\($dep) \(.id)"' todo.json > "$tmp/edges"
check "dependency graph is acyclic" tsort "$tmp/edges"

check "dependencies never point to later waves" jq -e '
  . as $root
  | ([$root.todos[]|{key:.id,value:.wave}]|from_entries) as $waves
  | all($root.todos[]; . as $item | all(.dependencies[]?; $waves[.] <= $item.wave))
' todo.json

check "program targets are production-shaped" jq -e '
  .program_targets.apply_capable_macros >= 24
  and .program_targets.simulate_capable_macros >= 40
  and .program_targets.real_repository_corpus >= 60
  and .program_targets.macro_gauntlet_cases >= 500
  and .program_targets.false_safe_apply == 0
  and .program_targets.interface_blocked_ratio_max <= 0.10
  and .program_targets.ai_structural_decisions == 0
' todo.json

check "research and operating contracts are explicit" jq -e '
  (.research_basis|length) >= 8
  and all(.research_basis[]; (.url|startswith("https://")) and (.lesson|length)>20)
  and (.operating_invariants|length) >= 7
  and (.definition_of_done|length) >= 5
' todo.json

printf '  passed: %s\n' "$pass"
printf '  failed: %s\n' "$fail"
[[ "$fail" -eq 0 ]]
