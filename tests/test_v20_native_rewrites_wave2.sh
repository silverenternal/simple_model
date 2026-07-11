#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(pwd)"; tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/jvm" "$tmp/clang"
printf 'class A {}\n' > "$tmp/jvm/A.java"
printf 'int main() { return 0; }\n' > "$tmp/clang/main.cpp"
jq -n '{language:"java",operation:"symbol_rename"}' > "$tmp/jvm-spec.json"
bash generators/openrewrite_adapter.sh --root "$tmp/jvm" --spec "$tmp/jvm-spec.json" --output "$tmp/jvm-report.json" --json >/dev/null
jq -e '.status=="review_only" and .native==false and .decision=="review_only" and .unsafe_fallback_apply==0' "$tmp/jvm-report.json" >/dev/null
jq -n '{language:"cpp",operation:"symbol_rename"}' > "$tmp/clang-spec.json"
bash generators/clang_refactor_adapter.sh --root "$tmp/clang" --spec "$tmp/clang-spec.json" --output "$tmp/clang-report.json" --json >/dev/null
jq -e '.status=="review_only" and .compilation_database==false and .unsafe_fallback_apply==0' "$tmp/clang-report.json" >/dev/null
printf '[]\n' > "$tmp/clang/compile_commands.json"
jq '.translation_unit_resolved=false' "$tmp/clang-spec.json" > "$tmp/clang-unresolved.json"
bash generators/clang_refactor_adapter.sh --root "$tmp/clang" --spec "$tmp/clang-unresolved.json" --output "$tmp/clang-unresolved-report.json" --json >/dev/null
jq -e '.status=="review_only" and .reason=="translation unit is unresolved"' "$tmp/clang-unresolved-report.json" >/dev/null
for language in java kotlin; do jq -e --arg l "$language" '(.languages|index($l))!=null and .type_attributed_required==true and .unsupported_policy=="review_only"' codemods/backends/jvm/backend.json >/dev/null; done
for language in c cpp; do jq -e --arg l "$language" '(.languages|index($l))!=null and .compilation_database_required==true and .unsupported_policy=="review_only"' codemods/backends/clang/backend.json >/dev/null; done
echo "  [OK] native rewrite wave2 JVM/Clang fail-closed optional adapters"
