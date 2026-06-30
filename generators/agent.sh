#!/usr/bin/env bash
# generators/agent.sh — AI agent CLI surface
# 用法: bash generators/agent.sh <subcommand> [args]
#
# 子命令:
#   status                          打印项目 dashboard（dashboard + 进度条）
#   next                            找下一个可领取的 todo（typewriter 输出）
#   claim <todo_id>                 认领 todo（spinner 动画）
#   complete <todo_id>              完成 todo（milestone 庆祝 + 解锁提示）
#   reset <todo_id>                 重置 todo 回 pending
#
# 数据来源:
#   .ai/dev_queue.json   — 任务清单（必需）
#   .bootstrap/state.json — 状态镜像（可选，存在时同步）
#
# 环境变量:
#   DEV_QUEUE_FILE    覆盖默认 dev_queue.json 路径
#   STATE_FILE        覆盖默认 state.json 路径
#   AGENT_NAME        写入 state.json.todos[id].agent 的认领者（默认 "ai-agent"）

set -euo pipefail

# ---------- 路径 ----------
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SELF_DIR/_lib.sh"

DEV_QUEUE_FILE="${DEV_QUEUE_FILE:-.ai/dev_queue.json}"
STATE_FILE="${STATE_FILE:-.bootstrap/state.json}"
STRUCT_FILE="${STRUCT_FILE:-./struct.json}"

# ---------- 覆盖 _lib.sh 的 spin_stop ----------
# 原版 spin_stop 在 set -e 下会因 kill 返回非零而 hang，这里吞掉错误码
spin_stop() {
    local exit_code="${1:-0}"
    if [[ -n "${SPIN_PID:-}" ]]; then
        kill "$SPIN_PID" 2>/dev/null || true
        wait "$SPIN_PID" 2>/dev/null || true
    fi
    printf '\r'
    if [[ $exit_code -eq 0 ]]; then
        printf '  [OK]   %s\n' "${spin_label:-}"
    else
        printf '  [FAIL] %s (exit=%d)\n' "${spin_label:-}" "$exit_code"
    fi
    SPIN_PID=""
}

# ---------- 工具函数 ----------
die()  { printf '  [FAIL] %s\n' "$*" >&2; exit 1; }
info() { printf '  [INFO] %s\n' "$*"; }

require_queue() {
    [[ -f "$DEV_QUEUE_FILE" ]] || die "找不到 $DEV_QUEUE_FILE；先跑 bootstrap.sh --target queue"
    jq empty "$DEV_QUEUE_FILE" 2>/dev/null || die "$DEV_QUEUE_FILE 不是合法 JSON"
}

require_todo_id() {
    [[ "$1" =~ ^[a-z][a-z0-9_]*$ ]] || die "todo_id 格式不合法: $1（要求 ^[a-z][a-z0-9_]*$）"
}

# 备份 + 写回（失败时回滚）
# 用法: safe_jq_update <jq_args...> -- <filter> <file>
# 例:   safe_jq_update --arg id "x" --arg st "done" -- '.foo | .bar' file.json
safe_jq_update() {
    local sep=""
    local jq_args=()
    local filter=""
    local file=""
    while [[ $# -gt 0 ]]; do
        if [[ "$1" == "--" ]]; then
            sep="--"; shift; break
        fi
        jq_args+=("$1"); shift
    done
    if [[ "$sep" != "--" ]]; then
        die "safe_jq_update: 缺少 -- 分隔符"
    fi
    filter="$1"; file="$2"

    local backup tmp
    backup="${file}.bak"
    tmp=$(mktemp)
    if [[ -f "$file" ]]; then
        cp "$file" "$backup"
    fi
    if jq "${jq_args[@]}" "$filter" "$file" > "$tmp" 2>/dev/null && jq empty "$tmp" 2>/dev/null; then
        mv "$tmp" "$file"
        rm -f "$backup"   # 成功 → 清理备份
        return 0
    else
        rm -f "$tmp"
        if [[ -f "$backup" ]]; then
            cp "$backup" "$file"
            info "已从备份回滚 $file"
        fi
        die "jq 改写 $file 失败"
    fi
}

# 同步 todo 状态到 state.json（如存在）
# 用法: sync_state_todo <todo_id> <new_status>
sync_state_todo() {
    local todo_id="$1" new_status="$2"
    [[ -f "$STATE_FILE" ]] || return 0
    [[ -f "$STATE_FILE.bak" ]] && [[ ! -f "$STATE_FILE" ]] && cp "$STATE_FILE.bak" "$STATE_FILE"

    local now
    now=$(date -u +%Y-%m-%dT%H:%M:%SZ)

    local agent_name="${AGENT_NAME:-ai-agent}"
    local jq_filter
    if [[ "$new_status" == "pending" ]]; then
        # 重置：清空 agent
        jq_filter="(.todos[\"$todo_id\"] //= {}) | .todos[\"$todo_id\"].status = \"$new_status\" | .todos[\"$todo_id\"].at = \"$now\" | .todos[\"$todo_id\"] |= (if has(\"agent\") then del(.agent) else . end)"
    else
        jq_filter="(.todos[\"$todo_id\"] //= {}) | .todos[\"$todo_id\"].status = \"$new_status\" | .todos[\"$todo_id\"].at = \"$now\" | .todos[\"$todo_id\"].agent = \"$agent_name\""
    fi

    safe_jq_update -- "$jq_filter" "$STATE_FILE"
}

# 找 todo 所在位置（wave index, todo index），输出 "<wave_idx>\t<todo_idx>"
locate_todo() {
    local todo_id="$1"
    jq -r --arg id "$todo_id" '
        (.waves // []) | to_entries[] as $w |
        $w.value.todos | to_entries[] |
        select(.value.id == $id) |
        "\($w.key)\t\(.key)"
    ' "$DEV_QUEUE_FILE"
}

# 计算 wave 进度（0..100）
wave_pct() {
    local wave_idx="$1"
    local stats
    stats=$(jq -r --argjson wi "$wave_idx" '
        .waves[$wi] as $w |
        ($w.todos | length) as $total |
        ([$w.todos[] | select(.status == "done")] | length) as $done |
        if $total == 0 then 100 else (($done * 100) / $total | floor) end
    ' "$DEV_QUEUE_FILE")
    echo "$stats"
}

# ---------- 子命令：status ----------
cmd_status() {
    require_queue

    # 顶层统计
    local modules components total_todos total_waves pending_cnt in_progress_cnt done_cnt blocked_cnt
    modules=$(jq -r '.modules // [] | length' "$STRUCT_FILE" 2>/dev/null || echo 0)
    components=$(jq -r '[.modules[].components // [] | length] | add // 0' "$STRUCT_FILE" 2>/dev/null || echo 0)
    total_todos=$(jq -r '.total_todos // ([.waves[].todos[].id] | length)' "$DEV_QUEUE_FILE")
    total_waves=$(jq -r '.total_waves // (.waves | length)' "$DEV_QUEUE_FILE")

    pending_cnt=$(jq '[.waves[].todos[] | select(.status == "pending")] | length' "$DEV_QUEUE_FILE")
    in_progress_cnt=$(jq '[.waves[].todos[] | select(.status == "in_progress")] | length' "$DEV_QUEUE_FILE")
    done_cnt=$(jq '[.waves[].todos[] | select(.status == "done")] | length' "$DEV_QUEUE_FILE")
    blocked_cnt=$(jq '[.waves[].todos[] | select(.status == "blocked")] | length' "$DEV_QUEUE_FILE")

    # 当前 wave：第一个还有 pending 或 in_progress 的 wave（1-indexed 显示）
    local current_wave
    current_wave=$(jq -r '
        [.waves | to_entries[] | .key as $wi | .value.todos as $todos |
            select(([$todos[] | select(.status == "done"), $todos[] | select(.status == "in_progress")] | length) > 0)
            | ($wi + 1)
        ] | .[0] // 1
    ' "$DEV_QUEUE_FILE")

    # 顶部 dashboard
    local body="modules: $modules  components: $components  todos: $total_todos
pending: $pending_cnt  in_progress: $in_progress_cnt  done: $done_cnt
waves: $total_waves  current_wave: $current_wave"
    box_draw "Project Status" "$body" 52

    echo ""

    # 每个 wave 一条 ascii_bar
    local wave_count
    wave_count=$(jq -r '.waves | length' "$DEV_QUEUE_FILE")
    local i=0
    while [[ $i -lt $wave_count ]]; do
        local wn todo_count pct
        wn=$(jq -r ".waves[$i].wave // $i" "$DEV_QUEUE_FILE")
        todo_count=$(jq -r ".waves[$i].todos | length" "$DEV_QUEUE_FILE")
        pct=$(wave_pct "$i")

        # 决定描述
        local desc="Wave $wn ($todo_count tasks"
        if [[ $i -eq 0 ]]; then
            desc="$desc, parallel-safe)"
        elif [[ $i -eq $((wave_count - 1)) && $i -gt 0 ]]; then
            desc="$desc, final wave)"
        else
            desc="$desc, depends on wave $((wn-1)))"
        fi
        printf '  %s\n' "$desc"
        ascii_bar "$pct" 38
        i=$((i + 1))
    done

    # 如果 state.json 存在，附状态
    if [[ -f "$STATE_FILE" ]]; then
        echo ""
        info "state.json 存在: $STATE_FILE"
    fi
}

# ---------- 子命令：next ----------
cmd_next() {
    local json_out="${1:-0}"
    require_queue

    # 找第一个 pending + high priority 的 todo（按 wave 顺序，再按 priority）
    local found
    found=$(jq -c '
        [.waves[] | .todos[] | select(.status == "pending")]
        | map(.priority as $p | .id as $i | {id: $i, priority: $p, sort_key: (if $p == "high" then 0 elif $p == "medium" then 1 else 2 end)})
        | sort_by(.sort_key)
        | .[0]
    ' "$DEV_QUEUE_FILE")

    if [[ "$found" == "null" || -z "$found" ]]; then
        if [[ "$json_out" == "1" ]]; then
            echo '{"error":"no pending todos"}'
            exit 1
        fi
        echo "  [INFO] 没有 pending 的 todo（全部 in_progress 或 done）"
        exit 1
    fi

    local todo_id
    todo_id=$(echo "$found" | jq -r '.id')

    # 拿完整元数据
    local meta
    meta=$(jq -c --arg id "$todo_id" '
        [.waves[].todos[] | select(.id == $id)][0]
    ' "$DEV_QUEUE_FILE")

    # --json 模式：只输出 JSON 到 stdout，机器友好
    if [[ "$json_out" == "1" ]]; then
        echo "$meta"
        exit 0
    fi

    local task component module blocks priority
    task=$(echo "$meta" | jq -r '.task')
    component=$(echo "$meta" | jq -r '.component')
    module=$(echo "$meta" | jq -r '.module')
    priority=$(echo "$meta" | jq -r '.priority')
    blocks=$(echo "$meta" | jq -r '.blocks | join(", ")')

    milestone "Next task for AI agent:"

    # 打字机显示详情
    typing_text "  todo_id   : $todo_id"
    typing_text "  task      : $task"
    typing_text "  component : $component"
    typing_text "  module    : $module"
    typing_text "  priority  : $priority"
    if [[ -n "$blocks" ]]; then
        typing_text "  blocks    : $blocks"
    else
        typing_text "  blocks    : (none)"
    fi

    # 机器可读 JSON 写到 stderr 末尾（方便 CI 抓取）
    echo ""
    info "machine-readable payload on stderr:"
    echo "$meta" >&2

    exit 0
}

# ---------- 子命令：claim ----------
cmd_claim() {
    require_queue
    local todo_id="${1:-}"
    require_todo_id "$todo_id"

    # 检查存在
    local located
    located=$(locate_todo "$todo_id")
    [[ -n "$located" ]] || die "todo 不存在: $todo_id"

    # 当前状态
    local cur_status
    cur_status=$(jq -r --arg id "$todo_id" '
        [.waves[].todos[] | select(.id == $id) | .status][0]
    ' "$DEV_QUEUE_FILE")

    if [[ "$cur_status" == "done" ]]; then
        die "todo $todo_id 已 done，不能 claim（先 reset）"
    fi

    spin_start "Claiming $todo_id"

    # 改 dev_queue.json
    safe_jq_update --arg id "$todo_id" --arg st "in_progress" -- '
        .waves |= map(.todos |= map(if .id == $id then .status = $st else . end))
    ' "$DEV_QUEUE_FILE"

    # 同步 state.json
    sync_state_todo "$todo_id" "in_progress"

    spin_stop 0

    # 新进度条
    local wi
    wi=$(echo "$located" | cut -f1)
    info "Wave $((wi+1)) 进度:"
    ascii_bar "$(wave_pct "$wi")" 38
}

# ---------- 子命令：complete ----------
cmd_complete() {
    require_queue
    local todo_id="${1:-}"
    require_todo_id "$todo_id"

    local located
    located=$(locate_todo "$todo_id")
    [[ -n "$located" ]] || die "todo 不存在: $todo_id"

    local cur_status
    cur_status=$(jq -r --arg id "$todo_id" '
        [.waves[].todos[] | select(.id == $id) | .status][0]
    ' "$DEV_QUEUE_FILE")

    if [[ "$cur_status" != "in_progress" ]]; then
        die "todo $todo_id 状态为 '$cur_status'，必须先 claim（in_progress）才能 complete"
    fi

    spin_start "Completing $todo_id"

    safe_jq_update --arg id "$todo_id" --arg st "done" -- '
        .waves |= map(.todos |= map(if .id == $id then .status = $st else . end))
    ' "$DEV_QUEUE_FILE"

    sync_state_todo "$todo_id" "done"

    spin_stop 0

    milestone "Completed: $todo_id"

    # 找出这个 todo 解锁了哪些 todo（自己的 blocks 字段就是它锁住的下游）
    local unlocked
    unlocked=$(jq -r --arg id "$todo_id" '
        [.waves[].todos[] | select(.id == $id) | (.blocks // [])[]][]
    ' "$DEV_QUEUE_FILE")

    if [[ -n "$unlocked" ]]; then
        info "解锁的下游 todos:"
        echo "$unlocked" | while IFS= read -r uid; do
            [[ -z "$uid" ]] && continue
            printf '    -> %s\n' "$uid"
        done
    else
        info "无下游解锁"
    fi

    # 当前进度
    local wi
    wi=$(echo "$located" | cut -f1)
    echo ""
    info "Wave $((wi+1)) 进度:"
    ascii_bar "$(wave_pct "$wi")" 38
}

# ---------- 子命令：reset ----------
cmd_reset() {
    require_queue
    local todo_id="${1:-}"
    require_todo_id "$todo_id"

    local located
    located=$(locate_todo "$todo_id")
    [[ -n "$located" ]] || die "todo 不存在: $todo_id"

    local cur_status
    cur_status=$(jq -r --arg id "$todo_id" '
        [.waves[].todos[] | select(.id == $id) | .status][0]
    ' "$DEV_QUEUE_FILE")

    spin_start "Resetting $todo_id"

    safe_jq_update --arg id "$todo_id" --arg st "pending" -- '
        .waves |= map(.todos |= map(if .id == $id then .status = $st else . end))
    ' "$DEV_QUEUE_FILE"

    sync_state_todo "$todo_id" "pending"

    spin_stop 0

    status_warn "reset $todo_id: $cur_status -> pending"

    local wi
    wi=$(echo "$located" | cut -f1)
    info "Wave $((wi+1)) 进度:"
    ascii_bar "$(wave_pct "$wi")" 38
}

# ---------- 入口 ----------
usage() {
    cat <<EOF
generators/agent.sh — AI agent CLI

用法:
  bash generators/agent.sh status
  bash generators/agent.sh next
  bash generators/agent.sh claim <todo_id>
  bash generators/agent.sh complete <todo_id>
  bash generators/agent.sh reset <todo_id>

数据文件:
  .ai/dev_queue.json    必需
  .bootstrap/state.json 可选（存在时同步）
EOF
}

main() {
    local sub="${1:-}"
    shift || true

    # 全局 --json 标志：仅 next/claim/complete/reset 支持
    local json_out=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) json_out=1; shift ;;
            *) break ;;
        esac
    done

    case "$sub" in
        status)   cmd_status ;;
        next)     cmd_next "$json_out" ;;
        claim)    cmd_claim "${1:-}" "$json_out" ;;
        complete) cmd_complete "${1:-}" "$json_out" ;;
        reset)    cmd_reset "${1:-}" "$json_out" ;;
        -h|--help|"") usage; exit 0 ;;
        *) die "未知子命令: $sub（用 --help 查看用法）" ;;
    esac
}

main "$@"