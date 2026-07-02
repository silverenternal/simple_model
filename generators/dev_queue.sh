#!/usr/bin/env bash
# generators/dev_queue.sh — 并行任务队列
# 输出:
#   .ai/dev_queue.json   机器可读：每个 wave 的 todo 列表
#   .ai/dev_queue.md     人类/AI 可读：每个 wave 的可领取任务清单
#
# 也可以被 source —— 只要设 DEV_QUEUE_LIB_ONLY=1，则只导出辅助函数
# （sync_todo_status）而不重新生成 dev_queue 文件。
set -euo pipefail
# 解析自身所在目录（兼容直接执行 和 source）
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    _DQ_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    _DQ_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
# shellcheck disable=SC1091
source "$_DQ_SELF_DIR/_lib.sh"
unset _DQ_SELF_DIR

# 被 source 时只加载辅助函数，不跑主体生成
if [[ "${DEV_QUEUE_LIB_ONLY:-0}" == "1" ]]; then
    # 同步单个 todo 状态（外部脚本可 source 调用）
    # 用法: sync_todo_status <todo_id> <new_status> [queue_file]
    #   queue_file 缺省: $OUTPUT_DIR/.ai/dev_queue.json 或 ./.ai/dev_queue.json
    sync_todo_status() {
        local todo_id="$1" new_status="$2" queue_file="${3:-}"
        if [[ -z "$queue_file" ]]; then
            queue_file="${OUTPUT_DIR:-.}/.ai/dev_queue.json"
        fi
        [[ -z "$queue_file" ]] && queue_file="./.ai/dev_queue.json"
        [[ ! -f "$queue_file" ]] && { echo "[FAIL] $queue_file 不存在" >&2; return 1; }
        local tmp
        tmp=$(mktemp)
        # 兼容两种结构:
        #   A) {todos: [...], waves: [{todos: [...]}]}
        #   B) 只有 waves: [{todos: [...]}]
        # 用 if-then-else 确保缺失字段不会被 iterate-over-null 报错。
        if jq --arg id "$todo_id" --arg st "$new_status" '
            if has("todos") then .todos |= map(if .id == $id then .status = $st else . end) else . end |
            .waves |= map(.todos |= map(if .id == $id then .status = $st else . end))
        ' "$queue_file" > "$tmp"; then
            mv "$tmp" "$queue_file"
            return 0
        else
            rm -f "$tmp"
            echo "[FAIL] jq 改写 $queue_file 失败" >&2
            return 1
        fi
    }
    export -f sync_todo_status 2>/dev/null || true
    return 0 2>/dev/null || exit 0
fi

AI_DIR="$OUTPUT_DIR/.ai"
mkdir -p "$AI_DIR"

# ---------- plan 模式 ----------
if [[ "${PLAN_ONLY:-0}" == "1" ]]; then
    echo "  PLAN: $AI_DIR/dev_queue.json"
    echo "  PLAN: $AI_DIR/dev_queue.md"
    exit 0
fi

# ============================================================
# 性能优化：单次 jq 调用预计算所有字段，存入关联数组
# 原方案：~500 次 jq 调用（45 todos × 11 次/todo）
# 优化后：3 次 jq 调用
# ============================================================

# ---------- 1. 单次 jq 提取所有 todo 元数据到 TSV ----------
# 字段顺序: id \t task \t priority \t status \t component \t module \t blocks_str \t notes \t ref
declare -A Q_TASK Q_PRI Q_STATUS Q_COMP Q_MOD Q_BLOCKS Q_BLOCKS_STR Q_NOTES Q_REF

while IFS=$'\t' read -r id task pri status comp mod blocks_str notes ref; do
    [[ -z "$id" ]] && continue
    Q_TASK[$id]="$task"
    Q_PRI[$id]="$pri"
    Q_STATUS[$id]="$status"
    Q_COMP[$id]="$comp"
    Q_MOD[$id]="$mod"
    Q_BLOCKS_STR[$id]="$blocks_str"
    # 纯 bash 构造 JSON 数组，避免 2 次 jq 调用
    if [[ -z "$blocks_str" ]]; then
        Q_BLOCKS[$id]="[]"
    else
        _bj="[" _bf=1
        for _b in $blocks_str; do
            [[ $_bf -eq 0 ]] && _bj+=","
            _bj+="\"$_b\""
            _bf=0
        done
        Q_BLOCKS[$id]="${_bj}]"
    fi
    Q_NOTES[$id]="$notes"
    Q_REF[$id]="$ref"
done < <(jq -r '
    .modules[] as $m | $m.components[] as $c | $c.todos[]? |
    [
        .id,
        .task,
        (.priority // "medium"),
        (.status // "pending"),
        $c.name,
        $m.name,
        ((.blocks // []) | join(" ")),
        (.notes // ""),
        (.ref // "")
    ] | @tsv
' "$STRUCT_FILE")

# ---------- 2. 单次 jq 生成每行 JSON 元数据 ----------
# 用于 dev_queue.json 的 todos 数组
# 输出格式: id<tab>json_object (每行一个)
declare -A Q_JSON_LINE
while IFS=$'\t' read -r id json_line; do
    [[ -z "$id" ]] && continue
    Q_JSON_LINE[$id]="$json_line"
done < <(jq -r '
    .modules[] as $m | $m.components[] as $c | $c.todos[]? |
    .id as $id |
    {id: $id, task, priority: (.priority // "medium"), status: (.status // "pending"),
     component: $c.name, module: $m.name, blocks: (.blocks // [])} |
    ($id + "\t" + tostring)
' "$STRUCT_FILE")

# ---------- 3. 计算 waves（来自 bootstrap.sh 的 compute_waves）----------
WAVES_TSV=$(compute_waves "$DEV_ORDER")

# ---------- 按 wave 号聚合 ----------
declare -A WAVE_MEMBERS
while IFS=$'\t' read -r wnum tid; do
    [[ -z "$wnum" ]] && continue
    WAVE_MEMBERS[$wnum]="${WAVE_MEMBERS[$wnum]:-}${WAVE_MEMBERS[$wnum]:+ }$tid"
done <<< "$WAVES_TSV"

# ---------- 输出 JSON ----------
{
    echo "{"
    echo "  \"schema_version\": \"4.0\","
    echo "  \"generated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"total_todos\": $TOTAL_TODOS,"
    echo "  \"total_waves\": $(echo "$WAVES_TSV" | cut -f1 | sort -un | wc -l),"
    echo "  \"waves\": ["

    first_wave=1
    for wnum in $(echo "$WAVES_TSV" | cut -f1 | sort -un); do
        [[ $first_wave -eq 0 ]] && echo ","
        first_wave=0
        members=$(echo "${WAVE_MEMBERS[$wnum]}" | tr ' ' '\n' | sort)
        todo_count=$(echo "$members" | wc -l)

        echo "    {"
        echo "      \"wave\": $wnum,"
        echo "      \"max_parallel\": $todo_count,"
        echo "      \"todos\": ["
        first_todo=1
        while IFS= read -r tid; do
            [[ -z "$tid" ]] && continue
            [[ $first_todo -eq 0 ]] && echo ","
            first_todo=0
            echo "        ${Q_JSON_LINE[$tid]}"
        done <<< "$members"
        echo ""
        echo "      ]"
        echo -n "    }"
    done
    echo ""
    echo "  ]"
    echo "}"
} > "$AI_DIR/dev_queue.json"

say "$AI_DIR/dev_queue.json"

# ---------- 输出 Markdown（给 AI / 人读）----------
{
    echo "# Dev Queue — 并行可领取任务清单"
    echo ""
    echo "> 自动生成于 $(date -u +%Y-%m-%dT%H:%M:%SZ) · 共 $TOTAL_TODOS 个 todo"
    echo ""
    echo "**用法（多 agent 并行开发）**："
    echo "1. 找到当前可领取的 wave（wave 1 永远可领取）"
    echo "2. 把同一个 wave 的 todo 分发给不同 agent 并行执行"
    echo "3. wave 内所有 todo 完成后，下一个 wave 自动解锁"
    echo ""
    echo "**用法（单 agent）**：按 wave 顺序逐个领取。"
    echo ""

    for wnum in $(echo "$WAVES_TSV" | cut -f1 | sort -un); do
        members=$(echo "${WAVE_MEMBERS[$wnum]}" | tr ' ' '\n' | sort)
        todo_count=$(echo "$members" | wc -l)

        echo "## Wave $wnum — ${todo_count} 个任务（可并行）"
        echo ""

        while IFS= read -r tid; do
            [[ -z "$tid" ]] && continue
            # 直接从关联数组读取，无需 jq
            priority="${Q_PRI[$tid]}"
            task="${Q_TASK[$tid]}"
            module="${Q_MOD[$tid]}"
            component="${Q_COMP[$tid]}"
            blocks_str="${Q_BLOCKS_STR[$tid]}"
            status="${Q_STATUS[$tid]}"

            emoji="[MED]"
            [[ "$priority" == "high" ]] && emoji="[HIGH]"
            [[ "$priority" == "low" ]] && emoji="[LOW]"

            echo "### $emoji \`$tid\` [$priority] — $status"
            echo "- **module / component**: \`$module\` / \`$component\`"
            echo "- **task**: $task"
            if [[ -n "$blocks_str" ]]; then
                echo "- **完成后解锁**: \`$blocks_str\`"
            else
                echo "- **完成后解锁**: (none)"
            fi
            notes="${Q_NOTES[$tid]}"
            ref="${Q_REF[$tid]}"
            [[ -n "$notes" && "$notes" != "" ]] && echo "- **notes**: $notes"
            [[ -n "$ref" && "$ref" != "" ]] && echo "- **ref**: $ref"
            echo ""
        done <<< "$members"
    done
} > "$AI_DIR/dev_queue.md"

say "$AI_DIR/dev_queue.md"

# 兼容老路径：dev_order.json（总序版本，保留向后兼容）
{
    echo "{"
    echo "  \"schema_version\": \"4.0\","
    echo "  \"generated_at\": \"$(date -u +%Y-%m-%dT%H:%M:%SZ)\","
    echo "  \"total_todos\": $TOTAL_TODOS,"
    echo "  \"order\": ["
    first=1
    for tid in $DEV_ORDER; do
        [[ $first -eq 0 ]] && echo ","
        printf '    "%s"' "$tid"
        first=0
    done
    echo ""
    echo "  ]"
    echo "}"
} > "$OUTPUT_DIR/dev_order.json"
say "$OUTPUT_DIR/dev_order.json"

# ---------- 外部脚本可调用的辅助函数 ----------
# （仅在 DEV_QUEUE_LIB_ONLY=1 被 source 时通过顶部 early-return 加载，
#  本体直接执行时也会重新导出，让同进程内其他脚本可见。）

# 同步单个 todo 状态（外部脚本可 source 调用）
# 用法: sync_todo_status <todo_id> <new_status> [queue_file]
#   queue_file 缺省: $OUTPUT_DIR/.ai/dev_queue.json 或 ./.ai/dev_queue.json
sync_todo_status() {
    local todo_id="$1" new_status="$2" queue_file="${3:-}"
    if [[ -z "$queue_file" ]]; then
        queue_file="${OUTPUT_DIR:-.}/.ai/dev_queue.json"
    fi
    [[ -z "$queue_file" ]] && queue_file="./.ai/dev_queue.json"
    [[ ! -f "$queue_file" ]] && { echo "[FAIL] $queue_file 不存在" >&2; return 1; }
    local tmp
    tmp=$(mktemp)
    # 兼容两种结构（见顶部说明）
    if jq --arg id "$todo_id" --arg st "$new_status" '
        if has("todos") then .todos |= map(if .id == $id then .status = $st else . end) else . end |
        .waves |= map(.todos |= map(if .id == $id then .status = $st else . end))
    ' "$queue_file" > "$tmp"; then
        mv "$tmp" "$queue_file"
        return 0
    else
        rm -f "$tmp"
        echo "[FAIL] jq 改写 $queue_file 失败" >&2
        return 1
    fi
}
export -f sync_todo_status 2>/dev/null || true
