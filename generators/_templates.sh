#!/usr/bin/env bash
# generators/_templates.sh — 模板系统辅助函数 (本文件独立于 _lib.sh)
# 提供: find_template, render_template, render_to_file
# 用法: source "$(dirname "${BASH_SOURCE[0]}")/_templates.sh"

# 模板目录: 用户可覆盖 ./templates/<lang>/<name>.tpl, 否则用 ./generators/templates_default/<lang>/<name>.tpl
TEMPLATE_DIR_USER="${TEMPLATE_DIR_USER:-./templates}"
TEMPLATE_DIR_DEFAULT="${GENERATORS_DIR:-$(dirname "${BASH_SOURCE[0]}")}/templates_default"

# find_template <lang> <name> -> 输出 .tpl 完整路径; 找不到输出空
find_template() {
    local lang="$1" name="$2"
    local user_path="$TEMPLATE_DIR_USER/$lang/$name.tpl"
    local default_path="$TEMPLATE_DIR_DEFAULT/$lang/$name.tpl"
    if [[ -f "$user_path" ]]; then
        echo "$user_path"
    elif [[ -f "$default_path" ]]; then
        echo "$default_path"
    else
        echo ""
    fi
}

# render_template <lang> <name> <vars_file>
# vars_file 是 key=value 文件, 模板里用 {{key}} 占位。
# 用 stdout 输出渲染结果。
render_template() {
    local lang="$1" name="$2"
    local vars="${3:-/dev/stdin}"
    local tpl_path
    tpl_path=$(find_template "$lang" "$name")
    if [[ -z "$tpl_path" ]]; then
        echo "[FAIL] template not found: $lang/$name.tpl" >&2
        return 1
    fi
    local sed_expr=""
    local key val escaped_val
    while IFS='=' read -r key val; do
        [[ -z "$key" || "$key" =~ ^# ]] && continue
        escaped_val=$(printf '%s' "$val" | sed 's/[&/\]/\\&/g')
        sed_expr+="s|{{$key}}|$escaped_val|g;"
    done < "$vars"
    sed "$sed_expr" "$tpl_path"
}

# render_to_file <out_path> <lang> <tpl_name> <vars_file>
# 若模板存在, 渲染并写入; 不存在则返回 1 (回退给调用方).
render_to_file() {
    local out_path="$1" lang="$2" tpl_name="$3" vars_file="$4"
    local tpl
    tpl=$(find_template "$lang" "$tpl_name")
    [[ -z "$tpl" ]] && return 1
    mkdir -p "$(dirname "$out_path")"
    render_template "$lang" "$tpl_name" "$vars_file" > "$out_path"
    return 0
}
