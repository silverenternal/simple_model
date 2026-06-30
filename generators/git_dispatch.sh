#!/usr/bin/env bash
# ============================================================================
# git_dispatch.sh — 把 .ai/dev_queue.json 当前 wave 的每个 todo 转成
#                   一个 git worktree，每个 worktree 一个独立分支，
#                   AI agent 在里面独立工作而不冲突。
#
# 零 Python 依赖：纯 bash + jq + git
#
# 接口（由 bootstrap.sh 或 supervisor 调用）:
#   --plan         列出 "would create worktree X for todo Y"，不实际创建
#   --wave N       调度指定 wave（默认 = wave 1）
#   --dry-run      同 --plan
#   -h | --help    显示帮助
#
# 用法:
#   bash generators/git_dispatch.sh --plan
#   bash generators/git_dispatch.sh --wave 1
# ============================================================================

set -euo pipefail

# ---------- 默认值 ----------
WAVE=1
PLAN_ONLY=0

# ---------- 帮助 ----------
usage() {
    cat <<'EOF'
git_dispatch.sh — 把 dev_queue.json 当前 wave 的 todos 分发到 git worktree

用法:
  bash git_dispatch.sh [--plan] [--wave N]

参数:
  --plan         只打印计划，不创建 worktree
  --wave N       指定 wave 号（默认 1）
  -h, --help     显示帮助

示例:
  bash git_dispatch.sh --plan                 # 看会创建哪些 worktree
  bash git_dispatch.sh --wave 1               # 实际创建 wave 1 的 worktree
  bash git_dispatch.sh --plan --wave 2        # 看 wave 2 计划
EOF
}

# ---------- 参数解析 ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --plan|--dry-run) PLAN_ONLY=1; shift ;;
        --wave)           WAVE="$2"; shift 2 ;;
        -h|--help)        usage; exit 0 ;;
        *)                echo "[FAIL] 未知参数: $1" >&2; usage; exit 1 ;;
    esac
done

# ---------- 依赖检查 ----------
command -v jq   >/dev/null 2>&1 || { echo "[FAIL] 缺少依赖: jq"   >&2; exit 1; }
command -v git  >/dev/null 2>&1 || { echo "[FAIL] 缺少依赖: git"  >&2; exit 1; }
command -v cp   >/dev/null 2>&1 || { echo "[FAIL] 缺少依赖: cp"   >&2; exit 1; }

# ---------- 路径解析 ----------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 用 git rev-parse --show-toplevel 找 git 根——优先用 CWD（脚本通常被 supervisor
# 从项目根调用），其次用 SCRIPT_DIR 所在仓库
GIT_ROOT=""
if git rev-parse --show-toplevel >/dev/null 2>&1; then
    GIT_ROOT="$(git rev-parse --show-toplevel)"
elif git -C "$SCRIPT_DIR" rev-parse --show-toplevel >/dev/null 2>&1; then
    GIT_ROOT="$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel)"
fi

if [[ -z "$GIT_ROOT" ]]; then
    echo "[FAIL] 当前不是 git 仓库（CWD=$(pwd), SCRIPT_DIR=$SCRIPT_DIR）" >&2
    exit 1
fi

PROJECT_ROOT="$GIT_ROOT"

# dev_queue.json 可能在 .ai/ 或 generated/.ai/（取决于 bootstrap.sh 的 --output）
DEV_QUEUE=""
for candidate in \
    "$GIT_ROOT/.ai/dev_queue.json" \
    "$GIT_ROOT/generated/.ai/dev_queue.json" \
    "$GIT_ROOT/generated_all/.ai/dev_queue.json"; do
    if [[ -f "$candidate" ]]; then
        DEV_QUEUE="$candidate"
        break
    fi
done

STRUCT_FILE="$GIT_ROOT/struct.json"
BOOTSTRAP="$GIT_ROOT/bootstrap.sh"

# struct.json 可能不是生成 dev_queue.json 的那个（用户可能跑了
# `bootstrap.sh -s examples/foo.json`，那 dev_queue 基于 foo.json，但
# 仓库根的 struct.json 是另一个）。自动检测：扫遍仓库里所有 *.json，
# 看哪个文件能"容纳" dev_queue.json 的所有 todo_id。
detect_struct_file() {
    local candidates=()
    [[ -f "$GIT_ROOT/struct.json" ]] && candidates+=("$GIT_ROOT/struct.json")
    # examples/ 下的所有 .json
    while IFS= read -r f; do
        [[ -n "$f" ]] && candidates+=("$f")
    done < <(find "$GIT_ROOT" -maxdepth 3 -name '*.json' \
             -not -path '*/.git/*' \
             -not -path '*/generated/*' \
             -not -path '*/generated_*/*' \
             -not -path '*/.ai/*' \
             2>/dev/null | sort)

    # 取 dev_queue 的 todo_id 个数和 module/component 总数做指纹
    local q_total
    q_total=$(jq '[.waves[].todos[]] | length' "$DEV_QUEUE" 2>/dev/null || echo 0)
    [[ "$q_total" -eq 0 ]] && return

    local best_file="" best_overlap=0 best_missing=999999

    for c in "${candidates[@]}"; do
        # 这个 candidate 的 (total - missing) = overlap with dev_queue
        # 比较 overlap 而不是 missing，因为不同 struct 可能都有部分覆盖
        local overlap missing
        overlap=$(jq --arg qids "$(jq -r '[.waves[].todos[].id] | join(" ")' "$DEV_QUEUE" 2>/dev/null)" '
            ([.modules[]?.components[]?.todos[]?.id // empty] | join(" ")) as $mine |
            ($qids | split(" ")) as $q |
            ($mine | split(" ")) as $m |
            ($q - ($q - $m)) | length
        ' "$c" 2>/dev/null || echo 0)
        missing=$(jq --arg qids "$(jq -r '[.waves[].todos[].id] | join(" ")' "$DEV_QUEUE" 2>/dev/null)" '
            ([.modules[]?.components[]?.todos[]?.id // empty] | join(" ")) as $mine |
            ($qids | split(" ")) as $q |
            ($q - ($q - $mine)) | length
        ' "$c" 2>/dev/null || echo 999999)

        # 优先 overlap 大、missing 少的
        if [[ "$overlap" -gt "$best_overlap" ]] || \
           { [[ "$overlap" -eq "$best_overlap" ]] && [[ "$missing" -lt "$best_missing" ]]; }; then
            best_file="$c"
            best_overlap="$overlap"
            best_missing="$missing"
        fi
    done

    [[ -n "$best_file" && "$best_overlap" -gt 0 ]] && echo "$best_file"
}

DETECTED_STRUCT=$(detect_struct_file || true)
if [[ -n "$DETECTED_STRUCT" && -f "$DETECTED_STRUCT" ]]; then
    STRUCT_FILE="$DETECTED_STRUCT"
fi

[[ -n "$DEV_QUEUE"  ]] || { echo "[FAIL] 找不到 dev_queue.json（请先跑 bootstrap.sh --target queue）" >&2; exit 1; }
[[ -f "$STRUCT_FILE" ]] || { echo "[FAIL] 找不到 $STRUCT_FILE" >&2; exit 1; }
[[ -f "$BOOTSTRAP"  ]] || { echo "[FAIL] 找不到 $BOOTSTRAP" >&2; exit 1; }

# ---------- 找 wave N 的 todos ----------
# dev_queue.json 结构: { ..., waves: [ { wave: N, max_parallel, todos: [...] } ] }
WAVE_DATA=$(jq -c --argjson w "$WAVE" '.waves[] | select(.wave == $w)' "$DEV_QUEUE")

if [[ -z "$WAVE_DATA" || "$WAVE_DATA" == "null" ]]; then
    echo "[FAIL] dev_queue.json 里没有 wave $WAVE（可用 wave: $(jq -c '[.waves[].wave]' "$DEV_QUEUE"))" >&2
    exit 1
fi

TODO_COUNT=$(echo "$WAVE_DATA" | jq '.todos | length')
WAVE_MAX_PARALLEL=$(echo "$WAVE_DATA" | jq '.max_parallel')

echo "============================================================"
echo " git_dispatch  repo=$GIT_ROOT"
echo " wave: $WAVE   todos: $TODO_COUNT   max_parallel: $WAVE_MAX_PARALLEL"
[[ $PLAN_ONLY -eq 1 ]] && echo " mode : PLAN ONLY (no writes)"
echo "============================================================"

# ---------- 工具函数 ----------

# todo_id_short <full_todo_id>
# 比如 api_http_interceptor -> http_interceptor（去掉模块前缀）
# 但更稳的做法是直接用完整 id 的安全版
todo_id_safe() {
    # 把 - / . / : 都换成 _，保证路径和分支名合法
    echo "$1" | tr '.-/ :' '_____'
}

# 找 todo 对应的 component 的 imports / exports / blocks / blocked_by
# 先从 dev_queue.json 拿 module/component（权威），再用 struct.json 补 imports/exports
# 输出 JSON 一行：{ todo_id, task, priority, component, module, imports, exports, blocks }
#
# 注意：所有 jq 调用都必须传文件参数，不能读 stdin——因为这个函数可能在
# `while read ... done < <(...)` 循环里被调用，stdin 已经被占用。
todo_full_meta() {
    local tid="$1"
    # 基本字段来自 dev_queue.json（每个 todo 都带 module / component / task / priority）
    local base
    base=$(jq -c --arg id "$tid" '
        [.waves[].todos[] | select(.id == $id)][0] // empty
    ' "$DEV_QUEUE")
    if [[ -z "$base" ]]; then
        return 1
    fi

    # 补 imports / exports / blocks：从 struct.json 拿
    local mod comp extras
    mod=$(printf '%s\n' "$base"   | jq -r '.module'     )
    comp=$(printf '%s\n' "$base"  | jq -r '.component'  )
    extras=$(jq -c --arg m "$mod" --arg c "$comp" --arg id "$tid" '
        .modules[] as $M | select($M.name == $m) |
        $M.components[] as $C | select($C.name == $c) |
        {
            imports: ($C.imports // []),
            exports: ($C.exports // []),
            blocks:  (([$C.todos[]? | select(.id == $id) | (.blocks // [])][0]) // [])
        }
    ' "$STRUCT_FILE" 2>/dev/null || echo '{}')

    # 显式 echo null 给 stdin，避免 jq 误读外部 stdin
    if [[ -z "$extras" ]]; then
        jq -c --argjson base "$base" '
            $base
            | { todo_id: .id, task: .task, priority: (.priority // "medium"),
                status: (.status // "pending"), component: .component, module: .module,
                imports: (.imports // []), exports: (.exports // []), blocks: (.blocks // []) }
        ' <<< 'null'
    else
        jq -c --argjson base "$base" --argjson extra "$extras" '
            $base + $extra
            | { todo_id: .id, task: .task, priority: (.priority // "medium"),
                status: (.status // "pending"), component: .component, module: .module,
                imports: (.imports // []), exports: (.exports // []), blocks: (.blocks // []) }
        ' <<< 'null'
    fi
}

# 反向索引：哪些 todo block 了给定 todo_id？
# 注意：必须传 stdin 显式 null（防止外层 while-read 占用 stdin）
todo_blocked_by() {
    local tid="$1"
    # 优先用 dev_queue.json 里其他 todo 的 blocks 字段反查
    local from_queue
    from_queue=$(jq -r --arg id "$tid" '
        [.waves[].todos[] | select((.blocks // []) | index($id)) | .id]
        | unique | .[]' "$DEV_QUEUE" < /dev/null 2>/dev/null)
    if [[ -n "$from_queue" ]]; then
        echo "$from_queue"
        return
    fi
    # 退化到 struct.json
    jq -r --arg id "$tid" '
        [.modules[] | . as $m | (.components // []) | .[] | . as $c |
         (.todos // []) | .[] | select((.blocks // []) | index($id)) | .id]
        | unique | .[]' "$STRUCT_FILE" < /dev/null 2>/dev/null
}

# ---------- 主循环 ----------

# worktree 根目录（同级目录下的 wt-*）
WT_PARENT="$(dirname "$GIT_ROOT")"

# 收集结果以便最后打印表格
declare -a SUMMARY_AGENT
declare -a SUMMARY_BRANCH
declare -a SUMMARY_PATH
declare -a SUMMARY_TODO
declare -a SUMMARY_STATUS

i=0
while IFS= read -r todo_line; do
    [[ -z "$todo_line" ]] && continue
    i=$((i + 1))

    TID=$(echo "$todo_line" | jq -r '.id')
    TID_SHORT=$(todo_id_safe "$TID")
    META=$(todo_full_meta "$TID")
    MOD=$(echo "$META"  | jq -r '.module')
    COMP=$(echo "$META" | jq -r '.component')
    TASK=$(echo "$META" | jq -r '.task')
    PRI=$(echo "$META"  | jq -r '.priority')
    MOD_SAFE=$(todo_id_safe "$MOD")
    COMP_SAFE=$(todo_id_safe "$COMP")

    BRANCH="wave/${WAVE}-${TID_SHORT}"
    WT_NAME="wt-${MOD_SAFE}-${COMP_SAFE}-${TID_SHORT}"
    WT_PATH="${WT_PARENT}/${WT_NAME}"

    echo ""
    echo "[$i/$TODO_COUNT] todo=$TID  branch=$BRANCH"
    echo "           module=$MOD  component=$COMP  priority=$PRI"

    if [[ $PLAN_ONLY -eq 1 ]]; then
        echo "  PLAN: would create worktree $WT_PATH for todo $TID"
        SUMMARY_AGENT+=("Agent $i")
        SUMMARY_BRANCH+=("$BRANCH")
        SUMMARY_PATH+=("$WT_PATH")
        SUMMARY_TODO+=("$TID")
        SUMMARY_STATUS+=("planned")
        continue
    fi

    # 1. 检查 worktree 是否已存在（git 注册的）
    if git -C "$GIT_ROOT" worktree list --porcelain | grep -q "^worktree $WT_PATH$"; then
        echo "  [WARN] worktree 已注册, 跳过: $WT_PATH"
        SUMMARY_STATUS+=("exists")
        SUMMARY_AGENT+=("Agent $i")
        SUMMARY_BRANCH+=("$BRANCH")
        SUMMARY_PATH+=("$WT_PATH")
        SUMMARY_TODO+=("$TID")
        continue
    fi

    # 1b. 如果目录残留（非注册的孤儿），先清理掉再创建
    if [[ -d "$WT_PATH" ]]; then
        echo "  [..] 清理残留目录: $WT_PATH"
        rm -rf "$WT_PATH"
    fi

    # 2. 检查分支是否已存在
    if git -C "$GIT_ROOT" show-ref --verify --quiet "refs/heads/$BRANCH"; then
        echo "  [WARN] 分支已存在, 复用并挂到 worktree: $BRANCH"
        git -C "$GIT_ROOT" worktree add "$WT_PATH" "$BRANCH"
    else
        # 3. 从 main（或当前分支）创建新分支 + worktree
        BASE_BRANCH="$(git -C "$GIT_ROOT" symbolic-ref --short HEAD 2>/dev/null || echo "main")"
        git -C "$GIT_ROOT" worktree add -b "$BRANCH" "$WT_PATH" "$BASE_BRANCH"
    fi

    # 4. 复制项目核心（整个项目 except generated/）
    #    用 rsync 排除 generated* 目录；没有 rsync 就用 cp + find 清理
    echo "  [..] 复制项目核心到 worktree（排除 generated*/）..."
    if command -v rsync >/dev/null 2>&1; then
        rsync -a --exclude='generated' --exclude='generated_*/' --exclude='.git/' \
              --exclude='wt-*/' \
              "$GIT_ROOT/" "$WT_PATH/"
    else
        # 退化方案：先 cp -a 再删 generated*
        cp -a "$GIT_ROOT/." "$WT_PATH/"
        find "$WT_PATH" -maxdepth 2 -type d \( -name 'generated' -o -name 'generated_*' \) \
            -exec rm -rf {} + 2>/dev/null || true
        rm -rf "$WT_PATH/.git"
    fi

    # 5. 跑 bootstrap.sh 在 worktree 内生成 agents / context / queue
    #    bootstrap.sh 的生成器把 .ai/ 写在 $OUTPUT_DIR/.ai/ 下，所以先把
    #    OUTPUT_DIR 设到 wt 下的 generated/，再把 generated/.ai/ 提到 wt 根的 .ai/
    echo "  [..] 跑 bootstrap.sh 生成 .ai/ ..."
    if (
        cd "$WT_PATH"
        rm -rf generated .ai
        bash ./bootstrap.sh --target agents,context,queue --no-validate \
            --output ./generated >/dev/null 2>&1
    ); then
        # 把 generated/.ai/ 移到 wt 根
        if [[ -d "$WT_PATH/generated/.ai" ]]; then
            mv "$WT_PATH/generated/.ai" "$WT_PATH/.ai"
        fi
        rm -rf "$WT_PATH/generated" 2>/dev/null || true
        echo "  [OK] bootstrap.sh 完成 (.ai/ 写到 wt 根)"
    else
        echo "  [WARN] bootstrap.sh 失败（继续写 task 文件）"
    fi

    # 6. 写 .ai/tasks/{todo_id}.md
    mkdir -p "$WT_PATH/.ai/tasks"
    TASK_FILE="$WT_PATH/.ai/tasks/${TID_SHORT}.md"
    BLOCKED_BY=$(todo_blocked_by "$TID" | tr '\n' ' ' | sed 's/ $//')
    BLOCKS=$(echo "$META" | jq -r '.blocks | join(", ")')
    IMPORTS=$(echo "$META" | jq -r '.imports | join(", ")')
    EXPORTS=$(echo "$META" | jq -r '.exports | join(", ")')

    {
        echo "# Task: \`$TID\`"
        echo ""
        echo "> Auto-generated by git_dispatch.sh · wave $WAVE · agent $i / $TODO_COUNT"
        echo ""
        echo "## Identity"
        echo ""
        echo "- **Todo ID**: \`$TID\`"
        echo "- **Module**: \`$MOD\`"
        echo "- **Component**: \`$COMP\`"
        echo "- **Priority**: \`$PRI\`"
        echo "- **Status**: \`pending\`"
        echo "- **Worktree**: \`$WT_PATH\`"
        echo "- **Branch**: \`$BRANCH\`"
        echo ""
        echo "## Task Description"
        echo ""
        echo "$TASK"
        echo ""
        echo "## Component Interface"
        echo ""
        echo "- **Exports**: \`${EXPORTS:-(none specified)}\`"
        echo "- **Imports**: \`${IMPORTS:-(none specified)}\`"
        echo ""
        echo "## Blockers"
        echo ""
        if [[ -n "$BLOCKED_BY" ]]; then
            echo "This task is **blocked by** (must be done first):"
            echo ""
            echo "- $BLOCKED_BY"
        else
            echo "This task has **no blockers** — it's at the head of wave $WAVE."
        fi
        echo ""
        echo "## Unlocks"
        echo ""
        if [[ -n "$BLOCKS" ]]; then
            echo "Completing this task **unlocks**:"
            echo ""
            echo "- $BLOCKS"
        else
            echo "Completing this task **unlocks nothing** (leaf task)."
        fi
        echo ""
        echo "## Workflow"
        echo ""
        echo "1. \`cd $WT_PATH\`"
        echo "2. Read \`AGENTS.md\` for project context."
        echo "3. Read \`.ai/dev_queue.json\` and \`.ai/dev_queue.md\`."
        echo "4. Implement the task described above."
        echo "5. Update \`.ai/dev_queue.json\`: set \`status: \"done\"\` for todo \`$TID\`."
        echo "6. Commit on branch \`$BRANCH\` and push / open PR when ready."
        echo ""
        echo "## Files You May Touch"
        echo ""
        echo "- Source files under \`src/<${MOD}>/\`"
        echo "- \`.ai/tasks/${TID_SHORT}.md\` (this file — update with progress notes)"
        echo "- \`.ai/dev_queue.json\` (status updates only)"
        echo ""
        echo "## Files You Must NOT Touch"
        echo ""
        echo "- \`struct.json\` — source of truth; fix the spec and regenerate."
        echo "- Other agents' worktrees (sibling \`wt-*\` directories)."
        echo ""
    } > "$TASK_FILE"

    echo "  [OK] task file: $TASK_FILE"

    SUMMARY_AGENT+=("Agent $i")
    SUMMARY_BRANCH+=("$BRANCH")
    SUMMARY_PATH+=("$WT_PATH")
    SUMMARY_TODO+=("$TID")
    SUMMARY_STATUS+=("created")
done < <(echo "$WAVE_DATA" | jq -c '.todos[]')

# ---------- Dispatch summary 表格 ----------
echo ""
echo "============================================================"
echo " DISPATCH SUMMARY — wave $WAVE"
echo "============================================================"

# 表头
printf "  %-10s %-32s %-28s %s\n" "AGENT" "BRANCH" "TODO" "STATUS"
printf "  %-10s %-32s %-28s %s\n" "----------" "--------------------------------" "----------------------------" "----------"

for idx in "${!SUMMARY_AGENT[@]}"; do
    printf "  %-10s %-32s %-28s %s\n" \
        "${SUMMARY_AGENT[$idx]}" \
        "${SUMMARY_BRANCH[$idx]}" \
        "${SUMMARY_TODO[$idx]}" \
        "${SUMMARY_STATUS[$idx]}"
done

echo ""
echo "------------------------------------------------------------"
echo " Agent commands (给主管 AI agent 看):"
echo "------------------------------------------------------------"
for idx in "${!SUMMARY_AGENT[@]}"; do
    printf "  %s: cd %s\n" "${SUMMARY_AGENT[$idx]}" "${SUMMARY_PATH[$idx]}"
done
echo ""
echo "============================================================"

if [[ $PLAN_ONLY -eq 1 ]]; then
    echo " PLAN COMPLETE — re-run without --plan to actually create worktrees."
else
    echo " DISPATCH COMPLETE — worktrees:"
    git -C "$GIT_ROOT" worktree list
fi
echo "============================================================"