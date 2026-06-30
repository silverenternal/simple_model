#!/usr/bin/env bash
# generators/context_json.sh — 机器可读的完整项目快照
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

OUT="$OUTPUT_DIR/.ai/context.json"

if [[ "${PLAN_ONLY:-0}" == "1" ]]; then
    echo "  PLAN: $OUT"
    exit 0
fi

mkdir -p "$OUTPUT_DIR/.ai"

# ---------- 1. 展开所有 todo（每条带 module/component 元信息）----------
TMP_TODOS_RAW=$(mktemp)
jq -c '
    .modules[] as $m | $m.components[] as $c |
    $c.todos[]? | . + {module: $m.name, component: $c.name}
' "$STRUCT_FILE" > "$TMP_TODOS_RAW"

# ---------- 2. wave 映射 ----------
TMP_TODO_WAVE=$(mktemp)
WAVES_TSV=$(compute_waves "$DEV_ORDER")
while IFS=$'\t' read -r wave tid; do
    [[ -z "$tid" ]] && continue
    # 从原始 todos 找这一条，加 wave
    jq -c --arg id "$tid" --argjson w "$wave" \
        'select(.id == $id) | . + {wave: $w}' "$TMP_TODOS_RAW" >> "$TMP_TODO_WAVE"
done <<< "$WAVES_TSV"

# ---------- 3. waves 聚合 ----------
TMP_WAVES=$(mktemp)
if [[ -n "$WAVES_TSV" ]]; then
    echo "$WAVES_TSV" | jq -R 'split("\t") | select(length == 2) | {wave: (.[0]|tonumber), todo_id: .[1]}' \
        | jq -s 'group_by(.wave) | map({wave: .[0].wave, todos: [.[].todo_id]}) | sort_by(.wave)' \
        > "$TMP_WAVES"
else
    echo "[]" > "$TMP_WAVES"
fi

CURRENT_WAVE=$(jq -r 'if length > 0 then (.[0].wave) else null end' "$TMP_WAVES")
if [[ -z "$CURRENT_WAVE" || "$CURRENT_WAVE" == "null" ]]; then
    CURRENT_WAVE=0
fi

# ---------- 4. 构造 context.json ----------
jq -n \
    --argjson modules "$(jq -c '
        [.modules[] | {
            name, description,
            language: (.language // "any"),
            components: [.components[] | {
                name, description,
                exports: (.exports // []),
                imports: (.imports // .depends_on // []),
                optional: (.optional // false),
                todo_count: ((.todos // []) | length)
            }]
        }]
    ' "$STRUCT_FILE")" \
    --slurpfile todos "$TMP_TODO_WAVE" \
    --slurpfile waves "$TMP_WAVES" \
    --argjson current_wave "$CURRENT_WAVE" \
    --arg schema_v "$(jq -r '.schema_version' "$STRUCT_FILE")" \
    --arg generated_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg desc "$(jq -r '.description // ""' "$STRUCT_FILE")" \
    '
    {
        schema_version: $schema_v,
        generated_at: $generated_at,
        description: $desc,
        summary: {
            modules: ($modules | length),
            components: ([$modules[].components | length] | add),
            total_todos: ($todos | length),
            pending_todos: ([$todos[] | select(.status == "pending")] | length),
            in_progress_todos: ([$todos[] | select(.status == "in_progress")] | length),
            done_todos: ([$todos[] | select(.status == "done")] | length)
        },
        modules: $modules,
        todos: $todos,
        waves: $waves,
        current_wave: $current_wave,
        ready_to_claim: [
            $todos[] | select(.wave == $current_wave and .status == "pending")
        ]
    }
    ' > "$OUT"

rm -f "$TMP_TODOS_RAW" "$TMP_TODO_WAVE" "$TMP_WAVES"

say "$OUT"