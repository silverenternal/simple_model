#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

pass=0
fail=0
EXIT_CODE=0

check(){
  local n="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    echo "  [OK]   $n"
    pass=$((pass+1))
  else
    echo "  [FAIL] $n"
    fail=$((fail+1))
    EXIT_CODE=1
  fi
}

TARGET="$ROOT_DIR/benchmarks/messy-repo-corpus/ts-python-go-monorepo"
OUTPUT="$TMP_DIR/capability-truth.json"
WRAP="$ROOT_DIR/codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh"

check "capability truth schema" \
  bash -c "bash \"$ROOT_DIR/generators/capability_truth_audit.sh\" --root \"$TARGET\" --struct \"$TARGET/struct.json\" --spec \"$ROOT_DIR/specs/capability-maturity.json\" --fixtures \"$TARGET\" --output \"$OUTPUT\" --json | jq -e '.capabilities and .maturity and .artifacts and .raw_commands'"

check "capability truth output is valid" test -s "$OUTPUT"
check "capability truth baseline fields" \
  bash -c "jq -e '(.ok|type == \"boolean\") and (.maturity.max_score == 5) and (.maturity.score|type == \"number\") and (.capabilities.analyze.ok|type == \"boolean\") and (.capabilities.generalization.ok|type == \"boolean\") and (.delta|type == \"object\")' \"$OUTPUT\""

check "wrapper executes capability-truth" \
  bash -c "'$WRAP' capability-truth --target-root '$TARGET' --struct '$TARGET/struct.json' --spec '$ROOT_DIR/specs/capability-maturity.json' --fixtures '$TARGET' --output '$OUTPUT.wrapper' --json | jq -e '(.ok|type==\"boolean\") and (.capabilities|type==\"object\")'"

check "command manifest documents capability-truth" \
  jq -e '.commands[] | select(.name=="capability-truth") | .tests|index("tests/test_v20_capability_truth_audit.sh") != null' \
    plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/references/command-manifest.json

check "command manifest has release gate" \
  jq -e '.commands[] | select(.name=="capability-truth") | .release_gate == true' plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/references/command-manifest.json

echo "  passed: $pass"
echo "  failed: $fail"
exit $EXIT_CODE
