#!/usr/bin/env bash
# _compat_patched
# ============================================================================
# git_merge.sh — 把 wave/* branches merge 到 main，并同步 .ai/dev_queue.json
#
# 零外部依赖: bash + jq + git
#
# 接口:
#   --plan           # dry-run: 列出 would merge branch X
#   --wave N         # 只 merge wave N 的 branches
#   (无参数)         # merge 所有 wave/* branches
#
# 退出码:
#   0   全部成功（或 plan 模式）
#   1   参数错误 / 缺依赖
#   2   部分 merge 失败（status 保留原值）
# ============================================================================
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/_lib.sh"
# 加载 sync_todo_status（不重新生成 dev_queue.json）
# shellcheck disable=SC1091
DEV_QUEUE_LIB_ONLY=1 source "$SCRIPT_DIR/dev_queue.sh"

# ---------- 默认值 ----------
OUTPUT_DIR="${OUTPUT_DIR:-.}"
QUEUE_FILE=""   # 留空 = 自动探测
PLAN_ONLY=0
WAVE_FILTER=""
TARGET_BRANCH=""   # 默认 = 当前 branch（通常是 main）

# ---------- 帮助 ----------
usage() {
    sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; s/^===.*/=/'
    exit "${1:-0}"
}

# ---------- 参数解析 ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --plan)         PLAN_ONLY=1; shift ;;
        --wave)         WAVE_FILTER="$2"; shift 2 ;;
        --target)       TARGET_BRANCH="$2"; shift 2 ;;
        --output-dir)   OUTPUT_DIR="$2"; shift 2 ;;
        --queue-file)   QUEUE_FILE="$2"; shift 2 ;;
        -h|--help)      usage 0 ;;
        *)              echo "[FAIL] 未知参数: $1" >&2; usage 1 ;;
    esac
done

# ---------- 自动探测 queue 文件 ----------
if [[ -z "$QUEUE_FILE" ]]; then
    # 优先级:
    #   1) $OUTPUT_DIR/.ai/dev_queue.json
    #   2) ./.ai/dev_queue.json
    #   3) ./generated/.ai/dev_queue.json (bootstrap.sh 默认)
    for cand in "$OUTPUT_DIR/.ai/dev_queue.json" "./.ai/dev_queue.json" "./generated/.ai/dev_queue.json"; do
        if [[ -f "$cand" ]]; then
            QUEUE_FILE="$cand"
            break
        fi
    done
fi

# ---------- 依赖检查 ----------
command -v jq >/dev/null 2>&1  || { echo "[FAIL] 缺少依赖: jq"   >&2; exit 1; }
command -v git >/dev/null 2>&1 || { echo "[FAIL] 缺少依赖: git"  >&2; exit 1; }
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "[FAIL] 当前目录不是 git 仓库" >&2; exit 1; }

# ---------- 决定 merge 目标 branch ----------
if [[ -z "$TARGET_BRANCH" ]]; then
    TARGET_BRANCH=$(git symbolic-ref --short HEAD 2>/dev/null || \
                    git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "main")
fi

# ---------- 列出 wave/* branches ----------
list_wave_branches() {
    local wave_num="$1"
    local pattern
    if [[ -n "$wave_num" ]]; then
        pattern="wave/${wave_num}-*"
    else
        pattern="wave/*-*"
    fi
    # --list 'wave/N-*' 形式（注意：本地 branch 不带 refs/heads/ 前缀）
    git for-each-ref --format='%(refname:short)' "refs/heads/$pattern" 2>/dev/null \
        | LC_ALL=C sort
}

# ---------- branch -> todo id 映射 ----------
# 规则: branch 形如 wave/N-<todo_id>，todo_id 保留原始大小写（通过 dev_queue.json 反查）
branch_to_todo_id() {
    local branch="$1"
    # branch 可能是 "wave/1-data_loader_1" 形式
    local tail="${branch#wave/}"        # 1-data_loader_1
    local after_dash="${tail#*-}"       # data_loader_1
    if [[ -z "$after_dash" || "$after_dash" == "$tail" ]]; then
        echo ""
        return
    fi
    echo "$after_dash"
}

# 反查: dev_queue.json 里所有 todo id -> 找与 branch 名匹配的（精确匹配）
resolve_todo_id() {
    local branch="$1"
    local candidate="$2"
    [[ ! -f "$QUEUE_FILE" ]] && { echo "$candidate"; return; }
    # 在 todos 数组里查找精确匹配的 id
    local hit
    hit=$(jq -r --arg c "$candidate" '
        (.todos // []) | map(select(.id == $c)) | .[0].id // empty
    ' "$QUEUE_FILE" 2>/dev/null)
    if [[ -n "$hit" ]]; then
        echo "$hit"
    else
        echo "$candidate"
    fi
}

# ---------- 主流程 ----------
MERGED=()
FAILED=()
SKIPPED=()

_compat_tmp_1=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
list_wave_branches "$WAVE_FILTER" > "${_compat_tmp_1}" 2>/dev/null || true
mapfile -t BRANCHES < "${_compat_tmp_1}"
rm -f "${_compat_tmp_1}"

if [[ ${#BRANCHES[@]} -eq 0 ]]; then
    echo "[INFO] 没有匹配的 wave/* branches（filter='${WAVE_FILTER:-all}'）" >&2
    exit 0
fi

echo "============================================================"
echo " git_merge  target=$TARGET_BRANCH  filter='${WAVE_FILTER:-all}'"
echo " 待处理 branches: ${#BRANCHES[@]}"
echo "============================================================"

# ---------- plan 模式 ----------
if [[ $PLAN_ONLY -eq 1 ]]; then
    for b in "${BRANCHES[@]}"; do
        echo "  would merge branch $b into $TARGET_BRANCH"
    done
    exit 0
fi

# ---------- 确保在目标 branch 上 ----------
CURRENT=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --abbrev-ref HEAD)
if [[ "$CURRENT" != "$TARGET_BRANCH" ]]; then
    echo "[INFO] 当前在 $TARGET_BRANCH 不在 $CURRENT，先 checkout..."
    git checkout "$TARGET_BRANCH" || {
        echo "[FAIL] 无法切换到 $TARGET_BRANCH" >&2; exit 1; }
fi

# ---------- 校验 queue 文件 ----------
if [[ -z "$QUEUE_FILE" || ! -f "$QUEUE_FILE" ]]; then
    echo "[WARN] 未找到 .ai/dev_queue.json —— 仅做 merge，不更新 status" >&2
    NO_QUEUE=1
    QUEUE_FILE=""
else
    NO_QUEUE=0
    echo "[INFO] queue file: $QUEUE_FILE"
fi

# ---------- 逐个 merge ----------
for branch in "${BRANCHES[@]}"; do
    # branch → todo id
    raw_id=$(branch_to_todo_id "$branch")
    if [[ -z "$raw_id" ]]; then
        echo "[SKIP] branch '$branch' 名字不符合 wave/N-<id> 格式，跳过"
        SKIPPED+=("$branch")
        continue
    fi
    if [[ $NO_QUEUE -eq 0 ]]; then
        todo_id=$(resolve_todo_id "$branch" "$raw_id")
    else
        todo_id="$raw_id"
    fi

    # 查最新 commit（用于日志）
    last_msg=$(git log -1 --format='%s' "$branch" 2>/dev/null || echo "?")

    echo ""
    echo "[MERGE] $branch  →  $TARGET_BRANCH"
    echo "        todo_id=$todo_id  last_commit=$last_msg"

    if git merge --no-ff "$branch" -m "merge $branch"; then
        status_ok "merged $branch"
        MERGED+=("$branch")

        # 更新 dev_queue.json
        if [[ $NO_QUEUE -eq 0 ]]; then
            if sync_todo_status "$todo_id" "done" "$QUEUE_FILE"; then
                status_ok "updated status: $todo_id -> done"
            else
                status_warn "更新 $todo_id status 失败（但 merge 已完成）"
            fi
        fi
    else
        rc=$?
        status_fail "merge $branch 失败（rc=$rc），冲突详情："
        echo "----------------------------------------------" >&2
        git status --short >&2 || true
        echo "----------------------------------------------" >&2
        echo "请手动解决冲突后: git add . && git commit --no-edit" >&2
        echo "解决后再次跑本脚本即可（已合并的 branch 会跳过）" >&2
        FAILED+=("$branch")

        # 中止 merge 让仓库回到可重入状态（不丢弃后续 branch）
        git merge --abort 2>/dev/null || true
    fi
done

# ---------- 报告 ----------
echo ""
echo "============================================================"
echo " Wave ${WAVE_FILTER:-all} 完成报告"
echo "============================================================"
echo "  target branch : $TARGET_BRANCH"
echo "  total branches: ${#BRANCHES[@]}"
echo "  merged        : ${#MERGED[@]}"
echo "  failed        : ${#FAILED[@]}"
echo "  skipped       : ${#SKIPPED[@]}"

if [[ ${#MERGED[@]} -gt 0 ]]; then
    echo ""
    echo "  [MERGED]"
    for b in "${MERGED[@]}"; do echo "    - $b"; done
fi
if [[ ${#FAILED[@]} -gt 0 ]]; then
    echo ""
    echo "  [FAILED] (status 未更新)"
    for b in "${FAILED[@]}"; do echo "    - $b"; done
fi
if [[ ${#SKIPPED[@]} -gt 0 ]]; then
    echo ""
    echo "  [SKIPPED]"
    for b in "${SKIPPED[@]}"; do echo "    - $b"; done
fi
if [[ $NO_QUEUE -eq 0 ]]; then
    echo ""
    echo "  dev_queue: $QUEUE_FILE"
else
    echo ""
    echo "  dev_queue: (未更新 — 找不到 .ai/dev_queue.json)"
fi
echo "============================================================"

# 退出码: 有失败 -> 2
if [[ ${#FAILED[@]} -gt 0 ]]; then
    exit 2
fi
exit 0