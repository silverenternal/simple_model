#!/usr/bin/env bash
# generators/typescript.sh — TypeScript 代码骨架生成器（纯 bash + jq）
# 约定:
#   - PascalCase 组件 -> snake_case 文件名
#   - 每个 component: export interface + export class
#   - 每个 module 一个目录: <module>/index.ts 重导出所有 component
#   - 顶层: tsconfig.json (strict, ES2022) + package.json (ESM)
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

LANG="typescript"
LANG_DIR="${OUTPUT_DIR}/${LANG}"
mkdir -p "$LANG_DIR"

# ---------- 顶层文件: tsconfig.json ----------
PKG_NAME=$(basename "$OUTPUT_DIR")
TSCONFIG_FILE="${LANG_DIR}/tsconfig.json"
if should_regenerate "$TSCONFIG_FILE" "$STRUCT_FILE"; then
    {
        echo "{"
        echo "  \"compilerOptions\": {"
        echo "    \"target\": \"ES2022\","
        echo "    \"module\": \"ESNext\","
        echo "    \"moduleResolution\": \"Bundler\","
        echo "    \"lib\": [\"ES2022\", \"DOM\", \"DOM.Iterable\"],"
        echo "    \"strict\": true,"
        echo "    \"noImplicitAny\": true,"
        echo "    \"strictNullChecks\": true,"
        echo "    \"esModuleInterop\": true,"
        echo "    \"skipLibCheck\": true,"
        echo "    \"forceConsistentCasingInFileNames\": true,"
        echo "    \"declaration\": true,"
        echo "    \"declarationMap\": true,"
        echo "    \"sourceMap\": true,"
        echo "    \"resolveJsonModule\": true,"
        echo "    \"isolatedModules\": true,"
        echo "    \"outDir\": \"./dist\","
        echo "    \"rootDir\": \".\""
        echo "  },"
        echo "  \"include\": [\"./**/*.ts\"],"
        echo "  \"exclude\": [\"node_modules\", \"dist\"]"
        echo "}"
    } > "$TSCONFIG_FILE"
    mark_generated "$TSCONFIG_FILE" "$STRUCT_FILE"
    say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/tsconfig.json"
else
    say "  [SKIP] ${LANG_DIR#$OUTPUT_DIR/}/tsconfig.json (unchanged)"
fi

# ---------- 顶层文件: package.json ----------
PACKAGE_FILE="${LANG_DIR}/package.json"
if should_regenerate "$PACKAGE_FILE" "$STRUCT_FILE"; then
    {
        echo "{"
        echo "  \"name\": \"$(echo "$PKG_NAME" | tr '[:upper:]' '[:lower:]')\","
        echo "  \"version\": \"0.1.0\","
        echo "  \"description\": \"Auto-generated TypeScript scaffold\","
        echo "  \"type\": \"module\","
        echo "  \"main\": \"./dist/index.js\","
        echo "  \"types\": \"./dist/index.d.ts\","
        echo "  \"scripts\": {"
        echo "    \"build\": \"tsc\","
        echo "    \"typecheck\": \"tsc --noEmit\","
        echo "    \"clean\": \"rm -rf dist\""
        echo "  },"
        echo "  \"devDependencies\": {"
        echo "    \"typescript\": \"^5.4.0\""
        echo "  }"
        echo "}"
    } > "$PACKAGE_FILE"
    mark_generated "$PACKAGE_FILE" "$STRUCT_FILE"
    say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/package.json"
else
    say "  [SKIP] ${LANG_DIR#$OUTPUT_DIR/}/package.json (unchanged)"
fi

# ---------- 模块与组件 ----------
N_MODULES=$(jq '.modules // [] | length' "$STRUCT_FILE")
for mi in $(seq 0 $((N_MODULES - 1))); do
    module_json=$(read_module "$mi")
    module_name=$(echo "$module_json" | jq -r '.name')
    module_lang=$(echo "$module_json" | jq -r '.language // "any"')
    module_desc=$(echo "$module_json" | jq -r '.description')

    # per-module language 过滤
    if [[ "$module_lang" != "any" && "$module_lang" != "$LANG" ]]; then
        say "跳过 ${module_name}（language=${module_lang}，不是 ${LANG}）"
        continue
    fi

    module_dir="${LANG_DIR}/${module_name}"
    mkdir -p "$module_dir"

    # 每个 component 一个 snake_case.ts 文件
    component_count=$(jq ".modules[$mi].components // [] | length" "$STRUCT_FILE")
    for ci in $(seq 0 $((component_count - 1))); do
        c_name=$(jq -r ".modules[$mi].components[$ci].name" "$STRUCT_FILE")
        c_desc=$(jq -r ".modules[$mi].components[$ci].description" "$STRUCT_FILE")
        c_exports=$(jq -c ".modules[$mi].components[$ci].exports // []" "$STRUCT_FILE")
        c_imports=$(jq -c ".modules[$mi].components[$ci].imports // .modules[$mi].components[$ci].depends_on // []" "$STRUCT_FILE")
        c_optional=$(jq -r ".modules[$mi].components[$ci].optional // false" "$STRUCT_FILE")
        c_todos_json=$(jq -c ".modules[$mi].components[$ci].todos // []" "$STRUCT_FILE")

        snake=$(to_snake "$c_name")
        file="${module_dir}/${snake}.ts"

        # ---------- 增量构建判断 ----------
        # sources = STRUCT_FILE（一切信息都来自 struct.json）
        if should_regenerate "$file" "$STRUCT_FILE"; then
            # 构建 import 块（同模块相对路径 / 跨模块 ../../<module>/<snake>）
            imports_block=""
            while IFS= read -r dep; do
                [[ -z "$dep" ]] && continue
                dep_module=$(module_of "$dep")
                [[ -z "$dep_module" ]] && continue
                dep_snake=$(to_snake "$dep")
                if [[ "$dep_module" == "$module_name" ]]; then
                    imports_block+="import { ${dep} } from \"./${dep_snake}\";"$'\n'
                else
                    imports_block+="import { ${dep} } from \"../${dep_module}/${dep_snake}\";"$'\n'
                fi
            done < <(echo "$c_imports" | jq -r '.[]')

            # exports 数组 -> TS 字面量（用于 JSDoc 注释）
            exports_list=""
            while IFS= read -r e; do
                [[ -z "$e" ]] && continue
                exports_list+=" *   - ${e}"$'\n'
            done < <(echo "$c_exports" | jq -r '.[]')

            # todos JSDoc 注释
            todos_block=""
            if [[ "$(echo "$c_todos_json" | jq 'length')" -gt 0 ]]; then
                todos_block=" *"$'\n'" * TODO:"$'\n'
                while IFS= read -r line; do
                    [[ -z "$line" ]] && continue
                    todos_block+=" *   - ${line}"$'\n'
                done < <(echo "$c_todos_json" | jq -r '.[] | "\(.id): \(.task) [priority=\(.priority // "medium")] [status=\(.status // "pending")] blocks=\(.blocks // [])"')
            fi

            cat > "$file" <<EOF
/**
 * Component: ${c_name} (module: ${module_name})
 *
 * ${c_desc}
 *
 * Auto-generated by bootstrap.sh — implement call().
${exports_list}${todos_block} */
$(echo "$imports_block" | sed '/^$/d')

/**
 * ${c_desc}
 */
export interface ${c_name}Options {
  readonly name: string;
  readonly optional: boolean;
}

/**
 * ${c_desc}
 *
 * Auto-generated by bootstrap.sh.
 */
export class ${c_name} implements ${c_name}Options {
  public readonly name: string = "${c_name}";
  public readonly optional: boolean = ${c_optional};

  /**
   * 执行 ${c_name} 的核心逻辑
   * 待实现：在子类或本类中填充具体行为
   */
  public call(): unknown {
    throw new Error("${c_name}.call() 待实现");
  }
}

export default ${c_name};
EOF
            mark_generated "$file" "$STRUCT_FILE"
            say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/${snake}.ts"
        else
            say "  [SKIP] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/${snake}.ts (unchanged)"
        fi
    done

    # ---------- module 的 index.ts（重导出所有 component）----------
    index_file="${module_dir}/index.ts"
    if should_regenerate "$index_file" "$STRUCT_FILE"; then
        {
            echo "/**"
            echo " * Module: ${module_name}"
            echo " *"
            echo " * ${module_desc}"
            echo " *"
            echo " * Auto-generated by bootstrap.sh"
            echo " */"
            echo ""
            cc=$(jq ".modules[$mi].components // [] | length" "$STRUCT_FILE")
            for ci in $(seq 0 $((cc - 1))); do
                c_name=$(jq -r ".modules[$mi].components[$ci].name" "$STRUCT_FILE")
                snake=$(to_snake "$c_name")
                echo "export { ${c_name} } from \"./${snake}\";"
            done
        } > "$index_file"
        mark_generated "$index_file" "$STRUCT_FILE"
        say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/index.ts"
    else
        say "  [SKIP] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/index.ts (unchanged)"
    fi

    # ---------- per-module todo.json ----------
    if [[ "$(jq "[.modules[$mi].components[].todos // [] | length] | add // 0" "$STRUCT_FILE")" -gt 0 ]]; then
        todo_file="${module_dir}/todo.json"
        if should_regenerate "$todo_file" "$STRUCT_FILE"; then
            module_todo_json "$mi" "$todo_file"
            mark_generated "$todo_file" "$STRUCT_FILE"
            say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/todo.json"
        else
            say "  [SKIP] ${LANG_DIR#$OUTPUT_DIR/}/${module_name}/todo.json (unchanged)"
        fi
    fi
done

# ---------- 顶层 src/index.ts（重导出所有 module）----------
TOP_INDEX="${LANG_DIR}/index.ts"
if should_regenerate "$TOP_INDEX" "$STRUCT_FILE"; then
    {
        echo "/**"
        echo " * ${PKG_NAME} — Auto-generated TypeScript entry point"
        echo " * Auto-generated by bootstrap.sh"
        echo " */"
        echo ""
        # 只导出 language 匹配的 module
        for mi in $(seq 0 $((N_MODULES - 1))); do
            mlang=$(jq -r ".modules[$mi].language // \"any\"" "$STRUCT_FILE")
            [[ "$mlang" != "any" && "$mlang" != "$LANG" ]] && continue
            mname=$(jq -r ".modules[$mi].name" "$STRUCT_FILE")
            echo "export * from \"./${mname}\";"
        done
    } > "$TOP_INDEX"
    mark_generated "$TOP_INDEX" "$STRUCT_FILE"
    say "  [OK] ${LANG_DIR#$OUTPUT_DIR/}/index.ts"
else
    say "  [SKIP] ${LANG_DIR#$OUTPUT_DIR/}/index.ts (unchanged)"
fi

# ---------- 用 tsc 做类型校验（如果可用）----------
if command -v tsc >/dev/null 2>&1; then
    echo ""
    say "  ▶ tsc --noEmit ..."
    # 在 package.json 所在目录运行；需要安装 typescript 才能解析依赖
    if (cd "$LANG_DIR" && tsc --noEmit --pretty false 2>&1); then
        say "  [OK] tsc --noEmit 通过"
    else
        say "  [WARN] tsc --noEmit 失败（生成的代码不能通过类型校验）" >&2
    fi
elif command -v npx >/dev/null 2>&1; then
    say "  [INFO] tsc 未全局安装；可运行 'npm install && npx tsc --noEmit' 验证"
else
    say "  [INFO] tsc / npx 都不可用，跳过类型校验"
fi

echo "  [OK] typescript 生成完成: $LANG_DIR/"