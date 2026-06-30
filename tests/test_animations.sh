#!/usr/bin/env bash
# tests/test_animations.sh — 验证 generators/_lib.sh 中 v9 新增的 10 个动画原语
# 用法: bash tests/test_animations.sh
# 不依赖 emoji / Python / 外部命令；在 set -euo pipefail 下安全运行。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck disable=SC1091
source "$ROOT_DIR/generators/_lib.sh"

pass=0
fail=0

# 比较两个字符串是否相等
equals() {
    [[ "$1" == "$2" ]]
}

contains() {
    [[ "$1" == *"$2"* ]]
}

run_check() {
    local name="$1" expected="$2" actual="$3"
    if contains "$actual" "$expected"; then
        printf '  [OK]   %s\n' "$name"
        pass=$((pass+1))
    else
        printf '  [FAIL] %s\n' "$name"
        printf '         expected contains: %q\n' "$expected"
        printf '         actual          : %q\n' "$actual"
        fail=$((fail+1))
    fi
}

echo "==============================================="
echo "  v9 Animation primitives — sanity checks"
echo "==============================================="
echo ""

# ---- 1. loading_dots ----
echo "[1] loading_dots"
# 写到临时文件以避免 subshell 问题
out_file=$(mktemp)
loading_dots "Fetching" 1 > "$out_file"
# 末尾应是 \r（清空行）
last_byte=$(tail -c 1 "$out_file" | od -An -c | tr -d ' ')
run_check "loading_dots emits [LOAD]" '[LOAD]' "$(cat "$out_file")"
# od 把 \r 输出为 \r；包含 'r' 即可
run_check "loading_dots final char is CR" 'r' "$last_byte"
rm -f "$out_file"
echo ""

# ---- 2. pulse_bar ----
echo "[2] pulse_bar"
out=$(pulse_bar 20)
# 输出全在一行（被 \r 覆盖）；直接 grep 即可
echo "$out" | cat -v
run_check "pulse_bar reaches 100%" '100%' "$out"
run_check "pulse_bar has [PULSE] tag" '[PULSE]' "$out"
echo ""

# ---- 3. rainbow_text ----
echo "[3] rainbow_text"
out=$(rainbow_text "Hi" 0.001)
echo "$out"
run_check "rainbow_text wraps with [#]" '[#]H' "$out"
run_check "rainbow_text second char wrapped" '[+]i[+]' "$out"
echo ""

# ---- 4. count_down ----
echo "[4] count_down"
out_file=$(mktemp)
count_down "Lift off" 2 > "$out_file"
content=$(tr '\r' '\n' < "$out_file")
echo "$content"
run_check "count_down shows T-2" 'T-2' "$content"
run_check "count_down shows T-1" 'T-1' "$content"
run_check "count_down shows GO!" 'GO!' "$content"
rm -f "$out_file"
echo ""

# ---- 5. wave_anim ----
echo "[5] wave_anim"
out=$(wave_anim "Tides" 1 | tr '\r' '\n' | tail -3)
echo "$out"
run_check "wave_anim has [WAVE]" '[WAVE]' "$out"
run_check "wave_anim has waves" '^' "$out"
echo ""

# ---- 6. section_banner ----
echo "[6] section_banner"
out=$(section_banner "Hello" 30)
echo "$out"
# 期望包含 +----------------------------+
run_check "section_banner top border" '+----------------------------+' "$out"
run_check "section_banner contains title" 'Hello' "$out"
run_check "section_banner bottom border" '+----------------------------+' "$out"
echo ""

# ---- 7. compare_bar ----
echo "[7] compare_bar"
out=$(compare_bar 75 100 "Tasks")
echo "$out"
run_check "compare_bar label" 'Tasks' "$out"
run_check "compare_bar ratio" '75/100 (75%)' "$out"
# 边界：超过 100%
out2=$(compare_bar 200 100)
echo "$out2"
run_check "compare_bar clamps to 100%" '200/100 (100%)' "$out2"
echo ""

# ---- 8. fireworks ----
echo "[8] fireworks"
out=$(fireworks "Done!" | tr '\r' '\n')
echo "$out"
run_check "fireworks banner" '*** Done! ***' "$out"
echo ""

# ---- 9. step ----
echo "[9] step"
# step 的 counter 持久化在 _LIB_STEP_COUNTER；但 $(step ...) 是 subshell，
# 会丢失改动。直接用 stdout 落文件验证。
_LIB_STEP_COUNTER=0
step_file=$(mktemp)
step "Connecting" 5 >> "$step_file"
step "Fetching" 5 >> "$step_file"
step "Finalize" 5 >> "$step_file"
content=$(cat "$step_file")
rm -f "$step_file"
echo "$content"
run_check "step counter starts at 1" '[STEP 1/5] Connecting' "$content"
run_check "step counter increments to 2" '[STEP 2/5] Fetching' "$content"
run_check "step counter increments to 3" '[STEP 3/5] Finalize' "$content"
echo ""

# ---- 10. header_line ----
echo "[10] header_line"
out=$(header_line)
echo "$out"
# 期望正好 60 个 -
dash60=$(printf -- '%.0s-' {1..60})
expected="  ${dash60}"
run_check "header_line default 60 dashes" "$expected" "$out"
out2=$(header_line '=' 40)
echo "$out2"
eq40=$(printf '=%.0s' {1..40})
run_check "header_line custom char + width" "  ${eq40}" "$out2"
echo ""

# ---- 总结 ----
echo "==============================================="
printf '  passed: %d\n  failed: %d\n' "$pass" "$fail"
echo "==============================================="

if [[ $fail -gt 0 ]]; then
    exit 1
fi