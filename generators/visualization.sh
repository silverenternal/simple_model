#!/usr/bin/env bash
# generators/visualization.sh — 架构可视化（甲方展示用）
# 输出 docs/ARCHITECTURE.md + docs/*.mmd + docs/architecture.html
set -euo pipefail
# _compat_patched
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

DOCS_DIR="$OUTPUT_DIR/docs"
mkdir -p "$DOCS_DIR"

if [[ "${PLAN_ONLY:-0}" == "1" ]]; then
    echo "  PLAN: $DOCS_DIR/ARCHITECTURE.md"
    echo "  PLAN: $DOCS_DIR/architecture.html"
    echo "  PLAN: $DOCS_DIR/module-graph.mmd"
    echo "  PLAN: $DOCS_DIR/phase-pipeline.mmd"
    echo "  PLAN: $DOCS_DIR/todo-blocker.mmd"
    exit 0
fi

# ---------- 1. module-graph.mmd: 模块/组件 DAG ----------
{
    echo "graph TD"
    echo "  classDef module fill:#e1f5ff,stroke:#01579b,stroke-width:2px"
    echo "  classDef component fill:#fff9c4,stroke:#f57f17,stroke-width:1px"
    echo "  classDef optional fill:#f5f5f5,stroke:#9e9e9e,stroke-dasharray: 5 5"
    echo ""

    # 模块节点
    _compat_tmp_1=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
    iter_modules > "${_compat_tmp_1}" 2>/dev/null || true
    while IFS=$'\t' read -r mi mname mdesc; do
        echo "  ${mname}[\"[MOD] ${mname}\"]:::module"
    done < "${_compat_tmp_1}"
    rm -f "${_compat_tmp_1}"

    # 组件到模块的边
    _compat_tmp_3=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
    iter_modules > "${_compat_tmp_3}" 2>/dev/null || true
    while IFS=$'\t' read -r mi mname mdesc; do
        _compat_tmp_2=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
        iter_components "$mi" > "${_compat_tmp_2}" 2>/dev/null || true
        while IFS=$'\t' read -r ci cname cdesc; do
            style=":::component"
            opt=$(jq -r ".modules[$mi].components[$ci].optional // false" "$STRUCT_FILE")
            [[ "$opt" == "true" ]] && style=":::optional"
            echo "  ${cname}[\"[CFG] ${cname}\"]${style}"
            echo "  ${mname} --> ${cname}"
        done < "${_compat_tmp_2}"
        rm -f "${_compat_tmp_2}"
    done < "${_compat_tmp_3}"
    rm -f "${_compat_tmp_3}"

    # 组件依赖边
    echo ""
    _compat_tmp_6=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
    iter_modules > "${_compat_tmp_6}" 2>/dev/null || true
    while IFS=$'\t' read -r mi mname mdesc; do
        _compat_tmp_5=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
        iter_components "$mi" > "${_compat_tmp_5}" 2>/dev/null || true
        while IFS=$'\t' read -r ci cname cdesc; do
            imports_json=$(jq -c ".modules[$mi].components[$ci].imports // .modules[$mi].components[$ci].depends_on // []" "$STRUCT_FILE")
            _compat_tmp_4=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
            echo "$imports_json" | jq -r '.[]' > "${_compat_tmp_4}" 2>/dev/null || true
            while IFS= read -r dep; do
                [[ -z "$dep" ]] && continue
                echo "  ${cname} -.uses.-> ${dep}"
            done < "${_compat_tmp_4}"
            rm -f "${_compat_tmp_4}"
        done < "${_compat_tmp_5}"
        rm -f "${_compat_tmp_5}"
    done < "${_compat_tmp_6}"
    rm -f "${_compat_tmp_6}"
} > "$DOCS_DIR/module-graph.mmd"
say "$DOCS_DIR/module-graph.mmd"

# ---------- 2. phase-pipeline.mmd: 阶段流水线 ----------
{
    echo "flowchart LR"
    echo "  classDef phase fill:#c8e6c9,stroke:#1b5e20,stroke-width:2px"
    echo ""

    phase_count=$(jq '.phases // [] | length' "$STRUCT_FILE")
    if [[ $phase_count -gt 0 ]]; then
        prev=""
        jq -r '.phases // [] | to_entries[] | "\(.key)\t\(.value.phase)\t\(.value.description)\t\(.value.mode)"' "$STRUCT_FILE" | while IFS=$'\t' read -r idx pname pdesc pmode; do
            echo "  P${idx}[\"[CFG] ${pname}<br/><i>${pmode}</i>\"]:::phase"
            [[ -n "$prev" ]] && echo "  ${prev} --> P${idx}"
            prev="P${idx}"
        done
    else
        echo "  P0[\"(no phases defined)\"]:::phase"
    fi
} > "$DOCS_DIR/phase-pipeline.mmd"
say "$DOCS_DIR/phase-pipeline.mmd"

# ---------- 3. todo-blocker.mmd: 任务 blocker DAG ----------
{
    echo "graph LR"
    echo "  classDef high fill:#ffcdd2,stroke:#b71c1c"
    echo "  classDef medium fill:#fff9c4,stroke:#f57f17"
    echo "  classDef low fill:#c8e6c9,stroke:#1b5e20"
    echo ""

    # 收集所有 todo
    TMP=$(mktemp)
    jq -r '
        .modules[] | .components[] | .todos[]? |
        [.id, (.priority // "medium")] | @tsv
    ' "$STRUCT_FILE" > "$TMP"

    while IFS=$'\t' read -r tid pri; do
        [[ -z "$tid" ]] && continue
        cls="medium"
        [[ "$pri" == "high" ]] && cls="high"
        [[ "$pri" == "low" ]] && cls="low"
        echo "  ${tid}[\"${tid}<br/><i>${pri}</i>\"]:::${cls}"
    done < "$TMP"
    rm -f "$TMP"

    # 边
    echo ""
    jq -r '
        (.modules // []) | .[] | (.components // []) | .[] | (.todos // []) | .[]? |
        select(.blocks) | [.id, (.blocks | join(","))] | @tsv
    ' "$STRUCT_FILE" | while IFS=$'\t' read -r src targets; do
        [[ -z "$src" ]] && continue
        IFS=',' read -ra arr <<< "$targets"
        for t in "${arr[@]}"; do
            [[ -n "$t" ]] && echo "  ${src} --> ${t}"
        done
    done
} > "$DOCS_DIR/todo-blocker.mmd"
say "$DOCS_DIR/todo-blocker.mmd"

# ---------- 4. ARCHITECTURE.md: 入口文档 ----------
PROJ_DESC=$(jq -r '.description // ""' "$STRUCT_FILE")
{
    echo "# Architecture Overview"
    echo ""
    echo "> Auto-generated from \`$STRUCT_FILE\`"
    echo ""
    echo "$PROJ_DESC"
    echo ""
    echo "## [DOCS] Module / Component Graph"
    echo ""
    echo "_黄色 = 核心组件 · 灰色虚线 = 可选组件 · 蓝色 = 模块_"
    echo ""
    echo '```mermaid'
    cat "$DOCS_DIR/module-graph.mmd"
    echo '```'
    echo ""
    echo "## [FLOW] Phase Pipeline"
    echo ""
    if [[ $phase_count -gt 0 ]]; then
        echo '_如果项目定义了 \`phases\`，按顺序展示执行流水线。_'
        echo ""
        echo '```mermaid'
        cat "$DOCS_DIR/phase-pipeline.mmd"
        echo '```'
    else
        echo "_No phases defined in this project._"
    fi
    echo ""
    echo "## [TODO] TODO Blocker Graph"
    echo ""
    echo "_[HIGH] 高优先级 · [MED] 中 · [LOW] 低 · 箭头表示\"完成后解锁\"_"
    echo ""
    echo '```mermaid'
    cat "$DOCS_DIR/todo-blocker.mmd"
    echo '```'
    echo ""
    echo "## [MOD] Module Inventory"
    echo ""
    echo "| Module | Components | Todos | Language | Description |"
    echo "|---|---:|---:|---|---|"
    _compat_tmp_7=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
    iter_modules > "${_compat_tmp_7}" 2>/dev/null || true
    while IFS=$'\t' read -r mi mname mdesc; do
        cn=$(component_count "$mi")
        tn=$(jq "[.modules[$mi].components[].todos // [] | length] | add // 0" "$STRUCT_FILE")
        lang=$(jq -r ".modules[$mi].language // \"any\"" "$STRUCT_FILE")
        echo "| \`${mname}\` | $cn | $tn | $lang | $mdesc |"
    done < "${_compat_tmp_7}"
    rm -f "${_compat_tmp_7}"
    echo ""
    echo "---"
    echo ""
    echo "_View this in a browser: open \`architecture.html\` in this directory._"
} > "$DOCS_DIR/ARCHITECTURE.md"
say "$DOCS_DIR/ARCHITECTURE.md"

# ---------- 5. architecture.html: 单文件可邮件给甲方 ----------
# 全部 Mermaid 内嵌，浏览器加载 CDN 即可渲染
{
    cat <<'HTML_HEAD'
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<title>Architecture Overview</title>
<style>
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Helvetica, Arial, sans-serif; max-width: 1100px; margin: 40px auto; padding: 0 20px; color: #222; line-height: 1.6; }
  h1 { border-bottom: 2px solid #1976d2; padding-bottom: 8px; }
  h2 { color: #1976d2; margin-top: 40px; }
  table { border-collapse: collapse; width: 100%; margin: 16px 0; }
  th, td { border: 1px solid #ddd; padding: 8px 12px; text-align: left; }
  th { background: #f5f5f5; }
  code { background: #f5f5f5; padding: 2px 6px; border-radius: 3px; font-size: 0.9em; }
  .meta { color: #666; font-size: 0.9em; }
  .mermaid { background: #fafafa; padding: 16px; border-radius: 8px; margin: 16px 0; }
</style>
</head>
<body>
HTML_HEAD

    echo "<h1>[ARCH] Architecture Overview</h1>"
    echo "<p class=\"meta\">Auto-generated from <code>$STRUCT_FILE</code></p>"
    echo "<p>$PROJ_DESC</p>"

    echo "<h2>[DOCS] Module / Component Graph</h2>"
    echo "<div class=\"mermaid\">"
    cat "$DOCS_DIR/module-graph.mmd"
    echo "</div>"

    echo "<h2>[FLOW] Phase Pipeline</h2>"
    if [[ $phase_count -gt 0 ]]; then
        echo "<div class=\"mermaid\">"
        cat "$DOCS_DIR/phase-pipeline.mmd"
        echo "</div>"
    else
        echo "<p><em>No phases defined in this project.</em></p>"
    fi

    echo "<h2>[TODO] TODO Blocker Graph</h2>"
    echo "<div class=\"mermaid\">"
    cat "$DOCS_DIR/todo-blocker.mmd"
    echo "</div>"

    echo "<h2>[MOD] Module Inventory</h2>"
    echo "<table><tr><th>Module</th><th>Components</th><th>Todos</th><th>Language</th><th>Description</th></tr>"
    _compat_tmp_8=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
    iter_modules > "${_compat_tmp_8}" 2>/dev/null || true
    while IFS=$'\t' read -r mi mname mdesc; do
        cn=$(component_count "$mi")
        tn=$(jq "[.modules[$mi].components[].todos // [] | length] | add // 0" "$STRUCT_FILE")
        lang=$(jq -r ".modules[$mi].language // \"any\"" "$STRUCT_FILE")
        echo "<tr><td><code>${mname}</code></td><td>$cn</td><td>$tn</td><td>$lang</td><td>${mdesc}</td></tr>"
    done < "${_compat_tmp_8}"
    rm -f "${_compat_tmp_8}"
    echo "</table>"

    cat <<'HTML_FOOT'
<script src="https://cdn.jsdelivr.net/npm/mermaid@10/dist/mermaid.min.js"></script>
<script>mermaid.initialize({startOnLoad:true, theme:'default', securityLevel:'loose'});</script>
</body>
</html>
HTML_FOOT
} > "$DOCS_DIR/architecture.html"
say "$DOCS_DIR/architecture.html"