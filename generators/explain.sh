#!/usr/bin/env bash
# generators/explain.sh — `bootstrap explain <component>` 命令实现
#
# 输出符合 specs/explain-output.json schema 的 JSON（或 markdown）。
# 用法:
#   bash generators/explain.sh <ComponentName>           # human-readable markdown
#   bash generators/explain.sh <ComponentName> --json    # machine-readable JSON
#
# 零 Python 依赖；只用 bash + jq。
set -euo pipefail
# _compat_patched

# 解析自身所在目录（兼容直接执行 和 source）
if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
    _EX_SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    _EX_SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
fi
# shellcheck disable=SC1091
source "$_EX_SELF_DIR/_lib.sh"
unset _EX_SELF_DIR

# ---------- 参数解析 ----------
COMPONENT="${1:-}"
JSON_OUT=0
if [[ $# -ge 2 && "$2" == "--json" ]]; then
    JSON_OUT=1
fi

if [[ -z "$COMPONENT" ]]; then
    echo "[FAIL] 用法: $0 <ComponentName> [--json]" >&2
    exit 64
fi

# ---------- 依赖 ----------
command -v jq >/dev/null 2>&1 || { echo "[FAIL] 缺少依赖: jq" >&2; exit 3; }

# 自动探测 STRUCT_FILE（如果 bootstrap 没 export）
if [[ -z "${STRUCT_FILE:-}" ]] || [[ ! -f "$STRUCT_FILE" ]]; then
    _CAND="$(pwd)/struct.json"
    [[ -f "$_CAND" ]] && STRUCT_FILE="$_CAND"
fi
[[ -f "$STRUCT_FILE" ]] || { echo "[FAIL] 找不到 struct.json" >&2; exit 4; }
unset _CAND

# 自动导出其他 _lib 需要的变量
export STRUCT_FILE
export GENERATORS_DIR="${GENERATORS_DIR:-$(dirname "${BASH_SOURCE[0]}")}"

# ---------- 找到 component ----------
MODULE=$(module_of "$COMPONENT")
if [[ -z "$MODULE" ]]; then
    echo "[FAIL] 在 $STRUCT_FILE 中找不到 component '$COMPONENT'" >&2
    exit 1
fi

# ---------- 加载动画 ----------
# JSON 模式：禁用 spinner（避免污染 stdout JSON）
if [[ $JSON_OUT -eq 1 ]]; then
    export NO_SPIN=1
fi
spin_start "Compiling context for $MODULE.$COMPONENT"

# 把对应 component 的完整 JSON 抽出来（含 todos）
COMP_JSON=$(jq -c --arg mod "$MODULE" --arg cmp "$COMPONENT" '
    .modules[] | select(.name == $mod) | .components[] | select(.name == $cmp)
' "$STRUCT_FILE")
if [[ -z "$COMP_JSON" ]]; then
    spin_stop 1
    echo "[FAIL] component JSON 抽取失败" >&2
    exit 1
fi

# ---------- schema 元信息 ----------
SCHEMA_V=$(jq -r '.schema_version' "$STRUCT_FILE")
GEN_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

# ---------- 计算 wave 号（沿用 _lib.compute_waves）----------
WAVES_TSV=$(compute_waves "$(topo_sort_todos)")
# 只挑属于当前 component 的 todo 的 wave
COMP_TODO_IDS=$(echo "$COMP_JSON" | jq -r '(.todos // [])[].id')
WAVE=1
if [[ -n "$COMP_TODO_IDS" ]]; then
    first_tid=$(echo "$COMP_TODO_IDS" | head -1)
    WAVE=$(awk -F'\t' -v id="$first_tid" '$2==id {print $1}' <<< "$WAVES_TSV" | head -1)
    [[ -z "$WAVE" ]] && WAVE=1
fi

# ---------- 上下游 / fan_in / fan_out ----------
# 用 contains 代替 index: 当 $c 不在数组里时 index 返回 null 导致 select 报 null-iterate
UPSTREAM=$(jq -r --arg c "$COMPONENT" '
    [.modules[] as $m | $m.components[] | select(((.imports // .depends_on // []) | contains([$c]))) | ($m | .name) + "." + .name] | unique | .[]
' "$STRUCT_FILE" 2>/dev/null || echo "")

# downstream_callees = 当前 component imports 了谁（完整地址 module.Name）
declare -a down_lines=()
_compat_tmp_1=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
echo "$COMP_JSON" | jq -r '(.imports // .depends_on // [])[]' > "${_compat_tmp_1}" 2>/dev/null || true
while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    dm=$(module_of "$d")
    [[ -z "$dm" ]] && dm=""
    if [[ -n "$dm" ]]; then
        down_lines+=("$dm.$d")
    else
        down_lines+=("$d")
    fi
done < "${_compat_tmp_1}"
rm -f "${_compat_tmp_1}"

if [[ ${#down_lines[@]} -gt 0 ]]; then
    DOWNSTREAM_LIST=$(printf '%s\n' "${down_lines[@]}" | jq -R '.' | jq -s 'unique')
else
    DOWNSTREAM_LIST="[]"
fi

FAN_IN=$(printf '%s\n' "$UPSTREAM" | jq -R '.' | jq -s 'length' 2>/dev/null || echo 0)
FAN_OUT=$(echo "$DOWNSTREAM_LIST" | jq 'length')

# ---------- critical_path 启发式 ----------
# 简单：fan_in > 0 视为可能在 critical path
CRITICAL="false"
[[ $FAN_IN -gt 0 ]] && CRITICAL="true"
# 把 UPSTREAM（new line list）转成 JSON 数组
UPSTREAM_JSON=$(printf '%s\n' "$UPSTREAM" | jq -R '.' | jq -s 'unique' 2>/dev/null || echo "[]")
# CRITICAL 转成 JSON boolean
CRITICAL_JSON="false"
[[ "$CRITICAL" == "true" ]] && CRITICAL_JSON="true"

# ---------- 收集 pending todos ----------
PENDING_JSON=$(echo "$COMP_JSON" | jq -c --argjson w "$WAVE" '
    [
        (.todos // [])[] |
        . + {wave: $w}
    ]
')
DONE_JSON="[]"

# ---------- callable_methods 推断 ----------
# 启发式: 从 todos 生成 do_<id> 方法签名
CALLOUT_JSON=$(echo "$COMP_JSON" | jq -c '
    [
        (.todos // [])[]? |
        {
            name: ("do_" + (.id | gsub("-"; "_"))),
            signature: ("def " + (.id | gsub("-"; "_")) + "(self) -> None"),
            returns: "None",
            docstring: .task,
            required: (.priority == "high")
        }
    ]
')

# ---------- exports ----------
EXPORTS_JSON=$(echo "$COMP_JSON" | jq -c '
    [
        (.exports // [])[]? | {
            name: .,
            type_hint: "class",
            description: ("export artifact: " + .)
        }
    ]')

# ---------- imports（每条带 module）----------
declare -a imp_arr=()
_compat_tmp_2=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
echo "$COMP_JSON" | jq -r '(.imports // .depends_on // [])[]' > "${_compat_tmp_2}" 2>/dev/null || true
while IFS= read -r d; do
    [[ -z "$d" ]] && continue
    dm=$(module_of "$d")
    [[ -z "$dm" ]] && dm=""
    imp_arr+=("$(jq -c -n --arg n "$d" --arg m "$dm" --arg w "needed by $COMPONENT per struct.json" \
        '{name:$n, module:$m, why:$w, specific_symbols:[]}')")
done < "${_compat_tmp_2}"
rm -f "${_compat_tmp_2}"
if [[ ${#imp_arr[@]} -gt 0 ]]; then
    IMPORTS_JSON=$(printf '%s\n' "${imp_arr[@]}" | jq -s '.')
else
    IMPORTS_JSON="[]"
fi

# ---------- hints 段 ----------
# files_to_read: 包含 spec 文档 + 当前 component 期望路径
FTR_FIRST=$(jq -c -n --arg mod "$MODULE" --arg comp "$COMPONENT" '
    [
        "specs/explain-output.json",
        "specs/context-bundle.json",
        "struct.json",
        ("generated/\($mod)/\($comp).py")
    ]
')
FTR_IMPORTS=$(echo "$IMPORTS_JSON" | jq -c '
    [
        "specs/lifecycle.json",
        (.[] | ("struct.json#" + .name))
    ]
')
_compat_ftr1=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
echo "$FTR_FIRST" > "$_compat_ftr1"
_compat_ftr2=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
echo "$FTR_IMPORTS" > "$_compat_ftr2"
FILES_TO_READ=$(jq -c -s 'add | unique' "$_compat_ftr1" "$_compat_ftr2")
rm -f "$_compat_ftr1" "$_compat_ftr2"

# files_to_create
FILES_TO_CREATE=$(jq -c -n --arg mod "$MODULE" --arg comp "$COMPONENT" '
    [
        ("generated/\($mod)/\($comp).py"),
        ("generated/\($mod)/tests/test_" + ($comp | ascii_downcase) + ".py")
    ]
')

# estimated_complexity: 启发式 — 看 todo 数 + priority high 数
HIGH_N=$(echo "$COMP_JSON" | jq '[(.todos // [])[] | select(.priority == "high")] | length')
TODO_N=$(echo "$COMP_JSON" | jq '(.todos // []) | length')
if [[ $TODO_N -le 1 && $HIGH_N -eq 0 ]]; then
    COMPLEXITY="trivial"
elif [[ $TODO_N -le 2 && $HIGH_N -le 1 ]]; then
    COMPLEXITY="easy"
elif [[ $TODO_N -le 4 && $HIGH_N -le 2 ]]; then
    COMPLEXITY="medium"
elif [[ $TODO_N -le 6 ]]; then
    COMPLEXITY="hard"
else
    COMPLEXITY="expert"
fi

IMPL_PATTERN="Mirror the structure of $MODULE sibling components (see struct.json). Implement the contract in specs/explain-output.json#interface; respect all imports and exports listed above."
COMMON_PITFALLS='["forgetting to update struct.json status after implementation","breaking existing exports (backward compat)","ignoring .optional flag (still need to be buildable)"]'
CONVENTIONS='["all class names use PascalCase matching struct.json","all public symbols exported via __all__","all imports declared in struct.json imports array"]'
EXAMPLE_TEST="def test_${COMPONENT,,}_contract():
    assert has_method(instance, '__init__')"

HINTS_JSON=$(jq -c -n \
    --argjson ftr "$FILES_TO_READ" \
    --argjson ftc "$FILES_TO_CREATE" \
    --arg pat "$IMPL_PATTERN" \
    --arg cplx "$COMPLEXITY" \
    --argjson pit "$COMMON_PITFALLS" \
    --argjson conv "$CONVENTIONS" \
    --arg ext "$EXAMPLE_TEST" \
    '{
        files_to_read: $ftr,
        files_to_create: $ftc,
        implementation_pattern: $pat,
        common_pitfalls: $pit,
        estimated_complexity: $cplx,
        conventions_to_follow: $conv,
        example_test: $ext
    }')

# ---------- 组装 explain JSON ----------
EXPLAIN_JSON=$(jq -n \
    --arg comp "$COMPONENT" \
    --arg mod "$MODULE" \
    --arg sv "$SCHEMA_V" \
    --arg gen "$GEN_AT" \
    --argjson exports "$EXPORTS_JSON" \
    --argjson imports "$IMPORTS_JSON" \
    --argjson methods "$CALLOUT_JSON" \
    --argjson pending "$PENDING_JSON" \
    --argjson done_ "$DONE_JSON" \
    --argjson upstream "$UPSTREAM_JSON" \
    --argjson downstream "$DOWNSTREAM_LIST" \
    --argjson wave "$WAVE" \
    --argjson crit "$CRITICAL_JSON" \
    --argjson fin "$FAN_IN" \
    --argjson fout "$FAN_OUT" \
    --argjson hints "$HINTS_JSON" \
    '
    {
        meta: {
            component: $comp,
            module: $mod,
            schema_version: $sv,
            generated_at: $gen
        },
        interface: {
            exports: $exports,
            imports: $imports,
            callable_methods: $methods
        },
        todos: {
            pending: $pending,
            done: $done_
        },
        relations: {
            upstream_callers: $upstream,
            downstream_callees: $downstream,
            wave: $wave,
            critical_path: $crit,
            fan_in: $fin,
            fan_out: $fout
        },
        hints: $hints
    }
')

# ---------- token 估算 ----------
# 启发式: 4 字符 ≈ 1 token（符合 schema meta.token_estimate 字段的注释）
TOKEN_EST=$(echo "$EXPLAIN_JSON" | wc -c | awk '{print int($1/4)}')
# 注入 meta.token_estimate
EXPLAIN_JSON=$(echo "$EXPLAIN_JSON" | jq --argjson te "$TOKEN_EST" '.meta.token_estimate = $te')

# ---------- 停止 spinner ----------
spin_stop 0

# ---------- 输出 ----------
if [[ $JSON_OUT -eq 1 ]]; then
    # 机器可读 JSON
    echo "$EXPLAIN_JSON" | jq .
    exit 0
fi

# ---------- 人类可读 markdown ----------
echo ""
box_draw "$COMPONENT" "module=$MODULE  wave=$WAVE  fan_in=$FAN_IN  fan_out=$FAN_OUT"

cat <<MDEOF
## meta
- **component**: \`$COMPONENT\`
- **module**: \`$MODULE\`
- **schema_version**: $SCHEMA_V
- **generated_at**: $GEN_AT
- **token_estimate**: ~$TOKEN_EST tokens

## interface

### exports
MDEOF

if [[ "$(echo "$EXPORTS_JSON" | jq 'length')" -eq 0 ]]; then
    echo "_(no exports declared)_"
else
    echo "$EXPORTS_JSON" | jq -r '.[] | "- `\(.name)` (type_hint=\(.type_hint // "n/a")): \(.description // "")"'
fi

echo ""
echo "### imports (downstream dependencies)"
if [[ "$(echo "$IMPORTS_JSON" | jq 'length')" -eq 0 ]]; then
    echo "_(no imports)_"
else
    echo "$IMPORTS_JSON" | jq -r '.[] | "- `\(.name)` (\(.module // "n/a")): \(.why // "")"'
fi

echo ""
echo "### callable_methods"
if [[ "$(echo "$CALLOUT_JSON" | jq 'length')" -eq 0 ]]; then
    echo "_(no callable methods inferred — derive from .todos entries)_"
else
    echo "$CALLOUT_JSON" | jq -r '.[] | "- `\(.name)` → `\(.signature // "")` (required=\(.required // false))"'
fi

echo ""
echo "## todos"

echo ""
echo "### pending ($(echo "$PENDING_JSON" | jq 'length'))"
if [[ "$(echo "$PENDING_JSON" | jq 'length')" -eq 0 ]]; then
    echo "_(no pending todos)_"
else
    echo "$PENDING_JSON" | jq -r '.[] | "- [\(.priority // "medium")] `\(.id)` — \(.task) (status=\(.status // "pending"), blocks=\(.blocks // [] | tostring))"'
fi

echo ""
echo "### done ($(echo "$DONE_JSON" | jq 'length'))"
echo "_(none)"

echo ""
echo "## relations"
echo "- **wave**: $WAVE"
echo "- **critical_path**: $CRITICAL"
echo "- **fan_in**: $FAN_IN"
echo "- **fan_out**: $FAN_OUT"
echo ""
echo "### upstream_callers"
if [[ "$(echo "$UPSTREAM" | jq 'length')" -eq 0 ]]; then
    echo "_(none)_"
else
    echo "$UPSTREAM" | jq -r '.[] | "- \(.)"'
fi

echo ""
echo "### downstream_callees"
if [[ "$(echo "$DOWNSTREAM_LIST" | jq 'length')" -eq 0 ]]; then
    echo "_(none)_"
else
    echo "$DOWNSTREAM_LIST" | jq -r '.[] | "- \(.)"'
fi

echo ""
echo "## hints"
echo ""
echo "### files_to_read"
echo "$HINTS_JSON" | jq -r '.files_to_read[] | "- \(.)"'
echo ""
echo "### files_to_create"
echo "$HINTS_JSON" | jq -r '.files_to_create[] | "- \(.)"'
echo ""
echo "### implementation_pattern"
echo "$HINTS_JSON" | jq -r '.implementation_pattern'
echo ""
echo "### estimated_complexity"
echo "\`$COMPLEXITY\`"
echo ""
echo "### common_pitfalls"
echo "$HINTS_JSON" | jq -r '.common_pitfalls[] | "- \(.)"'
echo ""
echo "### conventions_to_follow"
echo "$HINTS_JSON" | jq -r '.conventions_to_follow[] | "- \(.)"'

echo ""
echo "### example_test"
echo '```python'
echo "$HINTS_JSON" | jq -r '.example_test'
echo '```'

echo ""
token_counter "$TOKEN_EST" "estimated explain doc size"

exit 0