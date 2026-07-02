#!/usr/bin/env bash
# generators/python.sh — Python 代码骨架生成器（纯 bash + jq）
# 约定: PascalCase 组件 -> snake_case 文件，class 封装
set -euo pipefail
# _compat_patched
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

LANG="python"
LANG_DIR="${OUTPUT_DIR}/${LANG}"
# 布局: $LANG_DIR/<module>/<comp>.py + $LANG_DIR/<module>/__init__.py
#       $LANG_DIR/base.py
# 不再嵌 src/ 目录（避免相对 import 深度歧义）
mkdir -p "$LANG_DIR"

# to_snake / to_pascal 来自 _lib.sh (纯 bash 实现)

# 把 JSON 字符串数组 -> Python list literal
to_py_list() {
    jq -c '.' <<<"$1" | sed "s/^\[//; s/\]$//; s/^\"//; s/\"$//"
}

# 每个 module 的处理（用变量避免 zsh 的 {} 冲突）
N_MODULES=$(jq '.modules // [] | length' "$STRUCT_FILE")
for mi in $(seq 0 $((N_MODULES - 1))); do
    module_json=$(read_module "$mi")
    module_name=$(echo "$module_json" | jq -r '.name')
    module_lang=$(echo "$module_json" | jq -r '.language')
    module_desc=$(echo "$module_json" | jq -r '.description')

    # per-module language 过滤
    if [[ "$module_lang" != "any" && "$module_lang" != "$LANG" ]]; then
        say "跳过 ${module_name}（language=${module_lang}，不是 ${LANG}）"
        continue
    fi

    module_dir="${LANG_DIR}/${module_name}"
    mkdir -p "$module_dir"

    # __init__.py — 自动导出所有 component（解决 Bug #4：ImportError）
    init_py="${module_dir}/__init__.py"
    if should_regenerate "$init_py" "$STRUCT_FILE"; then
        {
            echo "\"\"\"Module: ${module_name}"
            echo ""
            echo "${module_desc}"
            echo "\"\"\""
            # re-export 每个 component，让 from data import DataLoader 能工作
            _compat_tmp_1=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
            jq -r ".modules[$mi].components[].name" "$STRUCT_FILE" > "${_compat_tmp_1}" 2>/dev/null || true
            while IFS= read -r comp; do
                [[ -z "$comp" ]] && continue
                snake_comp=$(to_snake "$comp")
                echo "from .${snake_comp} import ${comp}  # noqa: F401"
            done < "${_compat_tmp_1}"
            rm -f "${_compat_tmp_1}"
        } > "$init_py"
        mark_generated "$init_py" "$STRUCT_FILE"
        say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/__init__.py"
    else
        say "  [SKIP] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/__init__.py (unchanged)"
    fi

    # 每个 component 生成文件
    component_count=$(jq ".modules[$mi].components | length" "$STRUCT_FILE")
    for ci in $(seq 0 $((component_count - 1))); do
        c_name=$(jq -r ".modules[$mi].components[$ci].name" "$STRUCT_FILE")
        c_desc=$(jq -r ".modules[$mi].components[$ci].description" "$STRUCT_FILE")
        c_exports=$(jq -c ".modules[$mi].components[$ci].exports // []" "$STRUCT_FILE")
        c_imports=$(jq -c ".modules[$mi].components[$ci].imports // .modules[$mi].components[$ci].depends_on // []" "$STRUCT_FILE")
        c_optional=$(jq -r ".modules[$mi].components[$ci].optional // false" "$STRUCT_FILE")
        c_todos_json=$(jq -c ".modules[$mi].components[$ci].todos // []" "$STRUCT_FILE")

        snake=$(to_snake "$c_name")
        file="${module_dir}/${snake}.py"

        if should_regenerate "$file" "$STRUCT_FILE"; then
            # optional 转换成 Python bool
            if [[ "$c_optional" == "true" ]]; then
                optional_py="True"
            else
                optional_py="False"
            fi

            # 构建 import 块
            imports_block=""
            _compat_tmp_2=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
            echo "$c_imports" | jq -r '.[]' > "${_compat_tmp_2}" 2>/dev/null || true
            while IFS= read -r dep; do
                [[ -z "$dep" ]] && continue
                dep_module=$(module_of "$dep")
                [[ -z "$dep_module" ]] && continue
                dep_snake=$(to_snake "$dep")
                if [[ "$dep_module" == "$module_name" ]]; then
                    imports_block+="from .${dep_snake} import ${dep}"$'\n'
                else
                    imports_block+="from ..${dep_module}.${dep_snake} import ${dep}"$'\n'
                fi
            done < "${_compat_tmp_2}"
            rm -f "${_compat_tmp_2}"

            # produces list literal
            exports_py=$(echo "$c_exports" | jq -r '. | tostring')
            imports_py=$(echo "$c_imports" | jq -r '. | tostring')

            # todos 注释
            todos_block=""
            if [[ "$(echo "$c_todos_json" | jq 'length')" -gt 0 ]]; then
                todos_block="    # TODO:"$'\n'
                _compat_tmp_3=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
                echo "$c_todos_json" | jq -r '.[] | "\(.id): \(.task) [priority=\(.priority // "medium")] [\(.status // "pending")] blocks=\(.blocks // [])"' > "${_compat_tmp_3}" 2>/dev/null || true
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    todos_block+="    #   - ${line}"$'\n'
                done < "${_compat_tmp_3}"
                rm -f "${_compat_tmp_3}"
            fi

            {
                echo "\"\"\"Component: ${c_name} (module: ${module_name})"
                echo ""
                echo "${c_desc}"
                echo ""
                echo "Auto-generated by bootstrap.sh — implement __call__()."
                echo "\"\"\""
                echo "from typing import Any, List"
                echo "${imports_block}from ..base import Service as _BaseComponent"
                echo ""
                echo ""
                echo "class ${c_name}(_BaseComponent):"
                echo "    \"\"\"${c_desc}\"\"\""
                echo ""
                echo "    name: str = \"${c_name}\""
                echo "    exports: List[str] = ${exports_py}"
                echo "    imports: List[str] = ${imports_py}"
                echo "    optional: bool = ${optional_py}"
                echo ""
                [[ -n "$todos_block" ]] && echo "$todos_block"
                echo "    def __call__(self) -> Any:"
                echo "        \"\"\"执行 ${c_name} 的核心逻辑\"\"\""
                echo "        raise NotImplementedError(\"${c_name}.__call__() 待实现\")"
            } > "$file"
            mark_generated "$file" "$STRUCT_FILE"
            say "  [OK] ${module_name}/${snake}.py"
        else
            say "  [SKIP] ${module_name}/${snake}.py (unchanged)"
        fi
    done

    # per-module todo.json（如果有 todo 的话）
    if [[ "$(jq "[.modules[$mi].components[].todos // [] | length] | add // 0" "$STRUCT_FILE")" -gt 0 ]]; then
        todo_file="${module_dir}/todo.json"
        if should_regenerate "$todo_file" "$STRUCT_FILE"; then
            # Bug #8 fix: 每条 todo 都带 module + component 字段
            # 用 $mi 引用外层 module 索引（jq 内部没法直接看到 .modules[$mi].name）
            module_name_jq=$(jq -r ".modules[$mi].name" "$STRUCT_FILE")
            jq --arg mod "$module_name_jq" "{module: .modules[$mi].name, description: .modules[$mi].description, todos: [.modules[$mi].components[] | . as \$c | .todos[]? | . + {module: \$mod, component: \$c.name}]}" "$STRUCT_FILE" \
                > "$todo_file"
            mark_generated "$todo_file" "$STRUCT_FILE"
            say "  [OK] ${module_name}/todo.json"
        else
            say "  [SKIP] ${module_name}/todo.json (unchanged)"
        fi
    fi
done

# 顶层 base.py
mkdir -p "$LANG_DIR"
BASE_PY="${LANG_DIR}/base.py"
if should_regenerate "$BASE_PY" "$STRUCT_FILE"; then
    cat > "$BASE_PY" <<'PY'
"""Auto-generated base — do not edit, rerun bootstrap.sh"""
from abc import ABC, abstractmethod
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Type


@dataclass
class Service(ABC):
    """所有 component 的抽象基类"""
    name: str = ""
    exports: List[str] = field(default_factory=list)
    imports: List[str] = field(default_factory=list)
    optional: bool = False

    @abstractmethod
    def __call__(self) -> Any:
        raise NotImplementedError(f"{self.__class__.__name__}.__call__() 未实现")


class Registry:
    _r: Dict[str, Type[Service]] = {}
    @classmethod
    def register(cls, c): cls._r[c.name] = c; return c
    @classmethod
    def get(cls, n): return cls._r.get(n)
    @classmethod
    def all(cls): return dict(cls._r)
PY
    mark_generated "$BASE_PY" "$STRUCT_FILE"
    say "  [OK] base.py"
else
    say "  [SKIP] base.py (unchanged)"
fi

echo "  [OK] python 生成完成: $LANG_DIR/"

# 让整个 $LANG_DIR/ 成为一个可导入的 Python package
PACKAGE_INIT="${LANG_DIR}/__init__.py"
if should_regenerate "$PACKAGE_INIT" "$STRUCT_FILE"; then
    {
        echo "\"\"\"${LANG} — auto-generated package (do not edit)\"\"\""
        echo "__version__ = \"0.1.0\""
    } > "$PACKAGE_INIT"
    mark_generated "$PACKAGE_INIT" "$STRUCT_FILE"
    say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/__init__.py (package marker)"
fi

# pyproject.toml — 让 `python -m pip install -e .` 可用
PYPROJECT="${LANG_DIR}/pyproject.toml"
if should_regenerate "$PYPROJECT" "$STRUCT_FILE"; then
    cat > "$PYPROJECT" <<TOML
[build-system]
requires = ["setuptools>=68", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "${LANG}"
version = "0.1.0"
description = "Auto-generated from struct.json by bootstrap.sh"
requires-python = ">=3.9"
dynamic = ["dependencies"]

[tool.setuptools.packages.find]
include = ["${LANG}*"]
TOML
    mark_generated "$PYPROJECT" "$STRUCT_FILE"
    say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/pyproject.toml"
fi

# 顶层 README + 父 __init__.py（让 install -e 找到整个项目）
PARENT_DIR="$(dirname "$LANG_DIR")"
PARENT_INIT="${PARENT_DIR}/__init__.py"
if [[ ! -f "$PARENT_INIT" ]]; then
    echo "# Auto-generated parent package marker" > "$PARENT_INIT"
fi
PARENT_PYPROJECT="${PARENT_DIR}/pyproject.toml"
if [[ ! -f "$PARENT_PYPROJECT" && "$LANG_DIR" != "${OUTPUT_DIR}/${LANG}" ]]; then
    cat > "$PARENT_PYPROJECT" <<TOML
[build-system]
requires = ["setuptools>=68", "wheel"]
build-backend = "setuptools.build_meta"

[project]
name = "$(basename "$PARENT_DIR")"
version = "0.1.0"
description = "Auto-generated project root"
requires-python = ">=3.9"
TOML
fi

echo ""
echo "  用法:"
echo "    pip install -e ${LANG_DIR}"
echo "    python3 -c 'from ${LANG}.data import DataLoader; print(DataLoader)'"