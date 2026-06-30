#!/usr/bin/env bash
# generators/agents_md.sh — AI 启动入口 AGENTS.md
# 这是 AI agent 开始会话时应该读的"项目系统提示"
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

OUT="$OUTPUT_DIR/AGENTS.md"

if [[ "${PLAN_ONLY:-0}" == "1" ]]; then
    echo "  PLAN: $OUT"
    exit 0
fi

# ---------- 元信息 ----------
PROJ_DESC=$(jq -r '.description // "无描述"' "$STRUCT_FILE")
SCHEMA_V=$(jq -r '.schema_version' "$STRUCT_FILE")
N_MODULES=$(module_count)
N_COMPS=$(total_component_count)

# ---------- 当前可领取任务（wave 1）----------
# 找 wave 1 的 todo
WAVES_TSV=$(compute_waves "$DEV_ORDER")
WAVE1_IDS=$(echo "$WAVES_TSV" | awk -F'\t' '$1==1 {print $2}' | sort)

# ---------- 各 module 状态 ----------
declare -a MODULE_STATS
while IFS=$'\t' read -r mi mname mdesc; do
    [[ -z "$mi" ]] && continue
    todo_n=$(jq "[.modules[$mi].components // [] | .[].todos // [] | length] | add // 0" "$STRUCT_FILE")
    comp_n=$(jq ".modules[$mi].components // [] | length" "$STRUCT_FILE")
    lang=$(jq -r ".modules[$mi].language // \"any\"" "$STRUCT_FILE")
    MODULE_STATS+=("$mname|$comp_n|$todo_n|$lang|$mdesc")
done < <(iter_modules)

# ---------- 写 AGENTS.md ----------
{
    echo "# AGENTS.md — Project Working Agreement"
    echo ""
    echo "> Auto-generated from \`$STRUCT_FILE\` (schema v$SCHEMA_V)"
    echo "> Total: **$N_MODULES modules** / **$N_COMPS components** / **$TOTAL_TODOS todos**"
    echo ""
    echo "## [NOTE] Project Overview"
    echo ""
    echo "$PROJ_DESC"
    echo ""
    echo "## [START] Getting Started (AI agents: read this first)"
    echo ""
    echo "1. **Read this file completely** before doing anything."
    echo "2. **Check \`.ai/dev_queue.md\`** for the current parallel task queue (waves of work)."
    echo "3. **Pick a todo from Wave 1** (or the lowest-numbered wave with work remaining)."
    echo "4. **Check \`.ai/context.json\`** for the full machine-readable snapshot."
    echo "5. **Read the component's interface** (look at the module's existing files / specs)."
    echo "6. **Implement, run tests, mark done** — update \`.ai/dev_queue.json\` \`status\` field."
    echo ""
    echo "## [WAVE] Current Critical Path (Wave 1)"
    echo ""
    if [[ -z "$WAVE1_IDS" ]]; then
        echo "_没有 wave 1 的 todo（可能所有 blocker 都已解除，或 schema 里没 todos）_"
    else
        while IFS= read -r tid; do
            [[ -z "$tid" ]] && continue
            meta=$(jq -c --arg id "$tid" '
                [.[] | select(.id == $id)][0]
                | {task, priority: (.priority // "medium"), module: .module, component: .component}
            ' <(jq -c '
                [.modules[] | . as $m | (.components // []) | .[] | . as $c |
                 (.todos // []) | .[] | . + {module: $m.name, component: $c.name}]
            ' "$STRUCT_FILE"))
            pri=$(echo "$meta" | jq -r '.priority')
            task=$(echo "$meta" | jq -r '.task')
            mod=$(echo "$meta" | jq -r '.module')
            comp=$(echo "$meta" | jq -r '.component')
            emoji="[MED]"
            [[ "$pri" == "high" ]] && emoji="[HIGH]"
            [[ "$pri" == "low" ]] && emoji="[LOW]"
            echo "- $emoji **\`$tid\`** \`$mod.$comp\` — $task"
        done <<< "$WAVE1_IDS"
    fi
    echo ""
    echo "## [MOD] Module Status"
    echo ""
    echo "| Module | Components | Todos | Language | Description |"
    echo "|---|---:|---:|---|---|"
    for line in "${MODULE_STATS[@]}"; do
        IFS='|' read -r name cn tn lang desc <<< "$line"
        echo "| \`$name\` | $cn | $tn | $lang | $desc |"
    done
    echo ""
    echo "## [FILE] Where to Find Things"
    echo ""
    echo "- \`AGENTS.md\` — this file (read first)"
    echo "- \`.ai/context.json\` — full project snapshot (machine-readable)"
    echo "- \`.ai/dev_queue.json\` — parallel task queue with waves"
    echo "- \`.ai/dev_queue.md\` — same, human/AI-readable"
    echo "- \`dev_order.json\` — total topological order of todos (legacy)"
    echo ""
    echo "## [CFG] Rules of Engagement"
    echo ""
    echo "- **Never edit \`struct.json\` or generated artifacts by hand.** If the spec is wrong, fix the spec and regenerate."
    echo "- **Respect blocker DAG**: don't start a todo whose \`blocks\` references aren't all done."
    echo "- **Update \`.ai/dev_queue.json\` status** when you finish (pending → in_progress → done)."
    echo "- **Multiple agents can run in parallel** as long as they're in the same wave."
    echo ""
} > "$OUT"

say "$OUT"