#!/usr/bin/env bash
# generators/init.sh — bootstrap init 命令的 generator
# 用法: bash generators/init.sh --template <name> [--from <file>] [--from-url URL] [--output DIR]
#
# 实现四种模式:
#   1. --template <name>  从模板仓库（./templates/<name>/ 或 ./examples/<name>.json 或 ~/.bootstrap-templates/<name>/）脚手架
#   2. --from <file>      直接复制 .json 作为新项目的 struct.json
#   3. --from-url <url>   远程拉取（git+https / git+ssh / https / file://）→ cache → 应用 imports 合并 → 输出
#   4. 无参数              列出可用模板并交互选择
#
# 与 lifecycle.json#commands.init 对齐；退出码遵守 exit_code_legend。

set -euo pipefail
# _compat_patched

# ---------- 加载动画库 ----------
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"

# 注意: _lib.sh 的 spin_stop 在某些 bash 版本上会 hang（wait $SPIN_PID
# 在 SIGTERM 后不返回）。我们 wrap 一下，去掉那个 wait，保留视觉。
_INIT_SPIN_PID=""
_INIT_SPIN_LABEL=""
init_spin_start() {
    _INIT_SPIN_LABEL="$*"
    (
        local _chars='|/-\'
        local _i=0
        while true; do
            printf '\r  [%c] %s' "${_chars:_i++%4:1}" "$_INIT_SPIN_LABEL"
            sleep 0.1
        done
    ) &
    _INIT_SPIN_PID=$!
}
init_spin_stop() {
    local rc="${1:-0}"
    if [[ -n "$_INIT_SPIN_PID" ]]; then
        kill "$_INIT_SPIN_PID" 2>/dev/null || true
        disown "$_INIT_SPIN_PID" 2>/dev/null || true
        _INIT_SPIN_PID=""
    fi
    printf '\r'
    if [[ $rc -eq 0 ]]; then
        printf '  [OK]   %s\n' "$_INIT_SPIN_LABEL"
    else
        printf '  [FAIL] %s (exit=%d)\n' "$_INIT_SPIN_LABEL" "$rc"
    fi
}

# v9 P0: loading_dots 动画 —— 在耗时操作期间输出 . .. ... 的提示
# 用法: loading_dots <label> [seconds]
# - label: 显示文本
# - seconds: 持续时长（默认 2）
# 在 NO_SPIN=1 或非 tty 下会安静
loading_dots() {
    local label="$1" seconds="${2:-2}"
    [[ "${NO_SPIN:-0}" == "1" ]] && return 0
    if [[ ! -t 1 ]]; then
        printf '  ... %s\n' "$label"
        sleep "$seconds"
        return 0
    fi
    local i=0
    local end=$(( $(date +%s) + seconds ))
    while [[ $(date +%s) -lt $end ]]; do
        local dots=""
        local j=0
        while [[ $j -le $((i % 4)) ]]; do dots+='.'; j=$((j+1)); done
        printf '\r  [ ] %s%-3s' "$label" "$dots"
        sleep 0.25
        i=$((i+1))
    done
    printf '\r  [OK] %s\n' "$label"
}

# ---------- 默认值 ----------
TEMPLATE_NAME=""
FROM_FILE=""
FROM_URL=""
OUTPUT_DIR="."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE_CACHE_DIR="${HOME}/.bootstrap-templates"

# ---------- 参数解析 ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --template)    TEMPLATE_NAME="$2"; shift 2 ;;
        --from)        FROM_FILE="$2"; shift 2 ;;
        --from-url)    FROM_URL="$2"; shift 2 ;;
        --output)      OUTPUT_DIR="$2"; shift 2 ;;
        --cache-dir)   TEMPLATE_CACHE_DIR="$2"; shift 2 ;;
        --offline)     INIT_OFFLINE=1; shift ;;
        -h|--help)
            sed -n '2,/^# ====/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//; s/^===.*/=/'
            exit 0
            ;;
        *)
            echo "[FAIL] 未知参数: $1" >&2
            exit 64
            ;;
    esac
done

# ---------- 工具：解析模板 manifest ----------
# 输入: 模板目录或裸 .json 路径
# 输出 stdout: manifest JSON（裸 .json 时为 null）
# 全局副作用: TEMPLATE_DIR (str)
TEMPLATE_DIR=""
resolve_template_dir() {
    local name="$1"
    local candidate
    # 1. ./templates/<name>/
    candidate="$REPO_ROOT/templates/$name"
    if [[ -d "$candidate" ]]; then
        TEMPLATE_DIR="$candidate"; return 0
    fi
    # 2. ./examples/<name>.json  （裸 .json 当作 struct.json）
    candidate="$REPO_ROOT/examples/${name}.json"
    if [[ -f "$candidate" ]]; then
        TEMPLATE_DIR="$candidate"; return 0
    fi
    # 3. ~/.bootstrap-templates/<name>/
    candidate="$HOME/.bootstrap-templates/$name"
    if [[ -d "$candidate" ]]; then
        TEMPLATE_DIR="$candidate"; return 0
    fi
    return 1
}

# 从模板路径提取 struct.json 路径
# TEMPLATE_DIR 是目录  -> <dir>/<contents.struct_json or default struct.json>
# TEMPLATE_DIR 是文件  -> 当作裸 struct.json
resolve_struct_path() {
    local tdir="$1"
    if [[ -f "$tdir" ]]; then
        echo "$tdir"; return 0
    fi
    local manifest="$tdir/template.manifest.json"
    local rel="struct.json"
    if [[ -f "$manifest" ]]; then
        rel=$(jq -r '.contents.struct_json // "struct.json"' "$manifest")
    fi
    echo "$tdir/$rel"
}

# 从模板路径提取 manifest 路径（裸 .json 时输出空）
resolve_manifest_path() {
    local tdir="$1"
    if [[ -f "$tdir" ]]; then
        echo ""; return 0
    fi
    if [[ -f "$tdir/template.manifest.json" ]]; then
        echo "$tdir/template.manifest.json"
    else
        echo ""
    fi
}

# 把 JSON Pointer（/modules/0/name）转成 jq 路径（.modules[0].name）
jq_path_from_pointer() {
    local ptr="$1"
    local out=""
    local IFS='/'
    local seg
    for seg in $ptr; do
        [[ -z "$seg" ]] && continue
        if [[ "$seg" =~ ^[0-9]+$ ]]; then
            out+="[$seg]"
        else
            out+=".$seg"
        fi
    done
    echo "${out#.}"
}

# 在结构体里按 JSON Pointer 写值
# 用法: set_by_pointer <struct.json> <pointer> <value.json>
set_by_pointer() {
    local f="$1" ptr="$2" val="$3"
    local jq_path
    jq_path=$(jq_path_from_pointer "$ptr")
    local tmp
    tmp=$(mktemp)
    if jq -e "$jq_path" "$f" >/dev/null 2>&1; then
        # 字段已存在 -> 赋值（val 可能是字符串字面量或 JSON）
        if [[ "$val" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || [[ "$val" == "true" ]] || [[ "$val" == "false" ]] || [[ "$val" == "null" ]]; then
            jq --arg p "$jq_path" --argjson v "$val" 'setpath($p | split("."); $v)' "$f" > "$tmp" 2>/dev/null || \
            jq "$jq_path = $val" "$f" > "$tmp"
        elif [[ "$val" =~ ^\{.*\}$ ]] || [[ "$val" =~ ^\[.*\]$ ]]; then
            jq --argjson v "$val" "$jq_path = \$v" "$f" > "$tmp"
        else
            jq --arg v "$val" "$jq_path = \$v" "$f" > "$tmp"
        fi
    else
        # 字段不存在 -> 设值（jq setpath 会自动建中间对象，但数组下标不存在会报错）
        if [[ "$val" =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || [[ "$val" == "true" ]] || [[ "$val" == "false" ]] || [[ "$val" == "null" ]]; then
            jq --arg p "$jq_path" --argjson v "$val" 'setpath($p | split("."); $v)' "$f" > "$tmp" 2>/dev/null || \
            jq "$jq_path = $val" "$f" > "$tmp"
        elif [[ "$val" =~ ^\{.*\}$ ]] || [[ "$val" =~ ^\[.*\]$ ]]; then
            jq --argjson v "$val" "$jq_path = \$v" "$f" > "$tmp"
        else
            jq --arg v "$val" "$jq_path = \$v" "$f" > "$tmp"
        fi
    fi
    mv "$tmp" "$f"
}

# ---------- 自动生成的 .gitignore / .gitattributes / .githooks/ ----------
emit_gitignore() {
    local out="$1/.gitignore"
    if [[ -f "$out" ]]; then
        status_warn ".gitignore 已存在，跳过 ($out)"
        return 0
    fi
    cat > "$out" <<'EOF'
# ---- bootstrap 产物 ----
generated/
.bootstrap/state.json
.bootstrap/last_run.lock
.worktrees/
*.tmp
*.bak

# ---- 通用 ----
__pycache__/
*.py[cod]
node_modules/
target/
dist/
build/
.env
.env.local
.idea/
.vscode/
*.swp
EOF
    status_ok ".gitignore"
}

emit_gitattributes() {
    local out="$1/.gitattributes"
    if [[ -f "$out" ]]; then
        status_warn ".gitattributes 已存在，跳过"
        return 0
    fi
    cat > "$out" <<'EOF'
* text=auto eol=lf
*.png binary
*.jpg binary
*.gif binary
*.ico binary
*.pdf binary
*.zip binary
EOF
    status_ok ".gitattributes"
}

emit_githooks() {
    local dir="$1/.githooks"
    mkdir -p "$dir"
    local pre_commit="$dir/pre-commit"
    if [[ ! -f "$pre_commit" ]]; then
        cat > "$pre_commit" <<'EOF'
#!/usr/bin/env bash
# bootstrap 默认 pre-commit：struct.json 必须先 validate
set -e
if [[ -f ./struct.json ]] && command -v jq >/dev/null 2>&1; then
    jq empty ./struct.json || { echo "[FAIL] struct.json 不是合法 JSON" >&2; exit 1; }
    echo "  [OK] struct.json JSON 合法"
fi
EOF
        chmod +x "$pre_commit"
        status_ok ".githooks/pre-commit"
    fi
    # 写一个本地的 git config hint 文件
    local cfg="$dir/README.txt"
    if [[ ! -f "$cfg" ]]; then
        cat > "$cfg" <<'EOF'
bootstrap 默认 git hooks 目录。

启用方式（在项目根目录跑一次）：
    git config core.hooksPath .githooks
EOF
        status_ok ".githooks/README.txt"
    fi
}

# ---------- 模式 3：无参数 → 列出模板并询问 ----------
list_templates() {
    local -a names=()
    local -a descs=()
    local -a sources=()

    # 从 examples/*.json
    _compat_tmp_1=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
    find "$REPO_ROOT/examples" -maxdepth 1 -name '*.json' -type f 2>/dev/null | sort > "${_compat_tmp_1}" 2>/dev/null || true
    while IFS= read -r f; do
        local n
        n=$(basename "$f" .json)
        local d
        d=$(jq -r '.description // "(no description)"' "$f" 2>/dev/null || echo "(invalid json)")
        names+=("$n"); descs+=("$d"); sources+=("examples")
    done < "${_compat_tmp_1}"
    rm -f "${_compat_tmp_1}"

    # 从 ./templates/*/
    if [[ -d "$REPO_ROOT/templates" ]]; then
        _compat_tmp_2=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
        find "$REPO_ROOT/templates" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort > "${_compat_tmp_2}" 2>/dev/null || true
        while IFS= read -r d; do
            local n
            n=$(basename "$d")
            local m="$d/template.manifest.json"
            local desc="(directory)"
            if [[ -f "$m" ]]; then
                desc=$(jq -r '.identity.description // "(no description)"' "$m" 2>/dev/null || echo "(invalid manifest)")
            fi
            names+=("$n"); descs+=("$desc"); sources+=("templates/")
        done < "${_compat_tmp_2}"
        rm -f "${_compat_tmp_2}"
    fi

    # 从 ~/.bootstrap-templates/*/
    if [[ -d "$HOME/.bootstrap-templates" ]]; then
        _compat_tmp_3=$(mktemp "${TMPDIR:-/tmp}/sm_compat.XXXXXX")
        find "$HOME/.bootstrap-templates" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort > "${_compat_tmp_3}" 2>/dev/null || true
        while IFS= read -r d; do
            local n
            n=$(basename "$d")
            local m="$d/template.manifest.json"
            local desc="(user template)"
            if [[ -f "$m" ]]; then
                desc=$(jq -r '.identity.description // "(user template)"' "$m" 2>/dev/null || echo "(invalid manifest)")
            fi
            names+=("$n"); descs+=("$desc"); sources+=("~/.bootstrap-templates/")
        done < "${_compat_tmp_3}"
        rm -f "${_compat_tmp_3}"
    fi

    if [[ ${#names[@]} -eq 0 ]]; then
        echo "[FAIL] 找不到任何模板（examples/ templates/ ~/.bootstrap-templates/ 均为空）" >&2
        exit 1
    fi

    echo ""
    echo "============================================================"
    echo " bootstrap init — 可用模板"
    echo "============================================================"
    local body=""
    local i
    for i in "${!names[@]}"; do
        body+="$(printf '  %2d) [%-22s] %-14s  %s' "$((i+1))" "${sources[$i]}" "${names[$i]}" "${descs[$i]}")"$'\n'
    done
    box_draw "Available templates" "$(printf '%s' "$body" | sed '$d')"

    if [[ ! -t 0 ]]; then
        echo ""
        echo "提示: 非交互模式，请用 --template <name> 指定"
        exit 0
    fi

    echo ""
    echo -n "选择模板编号 (1-${#names[@]})，或输入 .json 文件路径: "
    read -r choice || true

    if [[ -z "$choice" ]]; then
        echo "[FAIL] 未选择模板" >&2
        exit 64
    fi

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#names[@]} ]]; then
        TEMPLATE_NAME="${names[$((choice-1))]}"
    elif [[ -f "$choice" ]]; then
        FROM_FILE="$choice"
    else
        echo "[FAIL] 无效选择: $choice" >&2
        exit 64
    fi
}

# ---------- 模式 2：--from <file> ----------
run_from_mode() {
    local src="$1"
    if [[ ! -f "$src" ]]; then
        echo "[FAIL] --from 指定的文件不存在: $src" >&2
        exit 4
    fi
    if ! jq empty "$src" 2>/dev/null; then
        echo "[FAIL] --from 指定的文件不是合法 JSON: $src" >&2
        exit 4
    fi

    mkdir -p "$OUTPUT_DIR"
    local target="$OUTPUT_DIR/struct.json"

    if [[ -f "$target" ]]; then
        if [[ ! -t 0 ]]; then
            echo "[FAIL] 目标已存在且非交互: $target" >&2
            echo "  提示: 换 --output 或手动删除" >&2
            exit 10
        fi
        echo -n "struct.json 已存在，覆盖？ [y/N]: "
        read -r ans || true
        [[ "$ans" =~ ^[Yy]$ ]] || { echo "  取消"; exit 0; }
    fi

    init_spin_start "Copying $src -> $target"
    cp "$src" "$target"
    init_spin_stop $?

    # v9 P0: 如果源 struct 顶部有 imports 字段，跑合并
    if jq -e 'has("imports") and (.imports | type == "array") and (length > 0)' "$target" >/dev/null 2>&1; then
        loading_dots "Resolving top-level imports" 1
        local merged
        merged=$(apply_imports "$target") || {
            echo "[FAIL] imports 合并失败" >&2
            exit 1
        }
        echo "$merged" > "$target"
        status_ok "applied top-level imports"
    fi

    # 估算 token 节省
    local bytes
    bytes=$(wc -c < "$target")
    local tokens=$(( bytes / 4 ))
    token_counter "$tokens" "copied as initial scaffold"

    echo ""
    status_ok "struct.json -> $target"
    emit_gitignore "$OUTPUT_DIR"
    emit_gitattributes "$OUTPUT_DIR"
    emit_githooks "$OUTPUT_DIR"

    milestone "Project scaffolded from $src"
}

# ---------- 模式 1：--template <name> ----------
run_template_mode() {
    local name="$1"

    if ! resolve_template_dir "$name"; then
        echo "[FAIL] 找不到模板 '$name'" >&2
        echo "  搜索路径:" >&2
        echo "    - $REPO_ROOT/templates/$name/" >&2
        echo "    - $REPO_ROOT/examples/${name}.json" >&2
        echo "    - $HOME/.bootstrap-templates/$name/" >&2
        echo "  提示: 不传参数可列出全部可用模板" >&2
        exit 1
    fi

    local struct_src
    struct_src=$(resolve_struct_path "$TEMPLATE_DIR")
    local manifest_path
    manifest_path=$(resolve_manifest_path "$TEMPLATE_DIR")

    if [[ ! -f "$struct_src" ]]; then
        echo "[FAIL] 模板缺少 struct.json: $struct_src" >&2
        exit 4
    fi
    if ! jq empty "$struct_src" 2>/dev/null; then
        echo "[FAIL] 模板的 struct.json 不是合法 JSON: $struct_src" >&2
        exit 4
    fi

    mkdir -p "$OUTPUT_DIR"
    local target="$OUTPUT_DIR/struct.json"

    if [[ -f "$target" ]]; then
        if [[ ! -t 0 ]]; then
            echo "[FAIL] struct.json 已存在且非交互: $target" >&2
            echo "  提示: 换 --output 或手动删除" >&2
            exit 10
        fi
        echo -n "struct.json 已存在，覆盖？ [y/N]: "
        read -r ans || true
        [[ "$ans" =~ ^[Yy]$ ]] || { echo "  取消"; exit 0; }
    fi

    echo "============================================================"
    echo " bootstrap init --template $name"
    echo "============================================================"
    echo "  source  : $TEMPLATE_DIR"
    [[ -n "$manifest_path" ]] && echo "  manifest: $manifest_path"
    echo "  target  : $target"
    echo "============================================================"
    echo ""

    # ---- 1. 解析 manifest.prompts ----
    if [[ -n "$manifest_path" && -t 0 ]]; then
        local n_prompts
        n_prompts=$(jq -r '.prompts // [] | length' "$manifest_path")
        if [[ "$n_prompts" -gt 0 ]]; then
            echo "[1/5] 交互式问题（$n_prompts 个）..."
            # 先把 struct.json 复制到 OUTPUT_DIR，再边问边改
            cp "$struct_src" "$target"
            local i=0
            while [[ $i -lt $n_prompts ]]; do
                local q_id q_text q_default q_options q_affects
                q_id=$(jq -r ".prompts[$i].id" "$manifest_path")
                q_text=$(jq -r ".prompts[$i].question" "$manifest_path")
                q_default=$(jq -r ".prompts[$i].default // empty" "$manifest_path")
                q_options=$(jq -r ".prompts[$i].options // [] | join(\"|\")" "$manifest_path")
                q_affects=$(jq -r ".prompts[$i].affects" "$manifest_path")

                echo ""
                printf '  [%d/%d] %s\n' "$((i+1))" "$n_prompts" "$q_text"
                if [[ -n "$q_default" && "$q_default" != "null" ]]; then
                    printf '        default: %s\n' "$q_default"
                fi
                if [[ -n "$q_options" ]]; then
                    printf '        options: %s\n' "$q_options"
                fi

                local answer=""
                if [[ ! -t 0 ]]; then
                    # 非交互：用 default
                    answer="$q_default"
                    echo "        (non-tty) -> default: $answer"
                else
                    echo -n "        > "
                    read -r answer || true
                    if [[ -z "$answer" ]]; then
                        answer="$q_default"
                    fi
                fi

                if [[ -z "$answer" ]]; then
                    status_warn "问题 '$q_id' 没回答，跳过（保留 default）"
                else
                    set_by_pointer "$target" "$q_affects" "$answer"
                    status_ok "$q_id = $answer -> $q_affects"
                fi

                i=$((i+1))
            done
        else
            init_spin_start "Scaffolding from template '$name'"
            cp "$struct_src" "$target"
            init_spin_stop $?
        fi
    else
        # 无 manifest 或非交互：直接 copy
        init_spin_start "Scaffolding from template '$name'"
        cp "$struct_src" "$target"
        init_spin_stop $?
    fi

    # ---- 2. 复制 supporting_files ----
    echo ""
    echo "[2/5] 复制 supporting files..."

    # v9 P0: 处理顶层 imports 字段（schema 复用）
    if jq -e 'has("imports") and (.imports | type == "array") and (length > 0)' "$target" >/dev/null 2>&1; then
        loading_dots "Resolving top-level imports" 1
        local merged
        merged=$(apply_imports "$target") || {
            echo "[FAIL] imports 合并失败" >&2
            exit 1
        }
        echo "$merged" > "$target"
        status_ok "applied top-level imports"
    fi
    if [[ -n "$manifest_path" ]]; then
        local n_sup
        n_sup=$(jq -r '.contents.supporting_files // [] | length' "$manifest_path")
        if [[ "$n_sup" -gt 0 ]]; then
            local j=0
            while [[ $j -lt $n_sup ]]; do
                local sup_path sup_required
                sup_path=$(jq -r ".contents.supporting_files[$j].path" "$manifest_path")
                sup_required=$(jq -r ".contents.supporting_files[$j].required" "$manifest_path")
                local src_file="$TEMPLATE_DIR/$sup_path"
                local dst_file="$OUTPUT_DIR/$sup_path"
                if [[ -f "$src_file" ]]; then
                    mkdir -p "$(dirname "$dst_file")"
                    cp "$src_file" "$dst_file"
                    status_ok "$sup_path"
                elif [[ "$sup_required" == "true" ]]; then
                    status_fail "missing required supporting file: $sup_path"
                    exit 4
                else
                    status_warn "optional supporting file not found: $sup_path"
                fi
                j=$((j+1))
            done
        else
            status_info "manifest 未声明 supporting_files"
        fi
    else
        # 裸 .json 模板没有 manifest，跳过 supporting_files 复制
        status_info "无 manifest，跳过 supporting_files"
    fi

    # ---- 3. 自动生成 .gitignore / .gitattributes / .githooks/ ----
    echo ""
    echo "[3/5] 生成 git 基础设施..."
    emit_gitignore "$OUTPUT_DIR"
    emit_gitattributes "$OUTPUT_DIR"
    emit_githooks "$OUTPUT_DIR"

    # ---- 4. 写 .bootstrap/state.json 镜像 ----
    echo ""
    echo "[4/5] 写 .bootstrap/state.json..."
    mkdir -p "$OUTPUT_DIR/.bootstrap"
    local state_file="$OUTPUT_DIR/.bootstrap/state.json"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local struct_hash
    struct_hash=$(sha256sum "$target" | awk '{print $1}')

    # template name / description (manifest 可选)
    local tpl_desc=""
    if [[ -n "$manifest_path" ]]; then
        tpl_desc=$(jq -r '.identity.description // ""' "$manifest_path" 2>/dev/null || true)
    fi
    [[ -z "$tpl_desc" ]] && tpl_desc=$(jq -r '.description // ""' "$target" 2>/dev/null || true)

    jq -n \
        --arg schema_v "1.0" \
        --arg at "$now" \
        --arg version "0.8.0" \
        --arg cmd "init" \
        --arg tpl "$name" \
        --arg tpl_desc "$tpl_desc" \
        --arg user "${USER:-unknown}@${HOSTNAME:-localhost}" \
        --arg hash "$struct_hash" \
        '{
            schema_version: $schema_v,
            last_run: {
                at: $at,
                version: $version,
                command: $cmd,
                argv: ["init", "--template", $tpl],
                exit_code: 0,
                duration_ms: 0,
                user: $user
            },
            struct_hash: $hash,
            struct_hash_history: [
                { at: $at, hash: $hash, reason: "init --template " + $tpl }
            ],
            stats: {
                generators_run: 0,
                files_written: 0,
                bytes_written: 0
            },
            errors: []
        }' > "$state_file"
    status_ok ".bootstrap/state.json"

    # ---- 5. 总结 ----
    echo ""
    echo "[5/5] 汇总..."
    local bytes
    bytes=$(wc -c < "$target")
    local tokens=$(( bytes / 4 ))
    # 模板帮你省下的 token ≈ 完整项目的 manifest + dev_queue + AGENTS.md 等
    local saved=$(( 30000 - tokens ))
    [[ $saved -lt 0 ]] && saved=0

    token_counter "$tokens" "in this struct.json"
    echo ""
    token_counter "$saved" "saved by scaffolding from template"

    echo ""
    echo "============================================================"
    status_ok "Template '$name' scaffolded"
    echo "============================================================"
    echo " 下一步:"
    echo "   cd $OUTPUT_DIR"
    echo "   jq . struct.json | head"
    echo "   git init && git add -A && git commit -m 'init from $name template'"
    echo "============================================================"

    milestone "Project '$name' ready"
}

# ---------- v9 P0: URL 解析 + 缓存 + imports 合并 ----------

# 解析 URL 协议/类型
# 输入: $1=url
# 输出 4 个全局变量: _URL_PROTO, _URL_BODY, _URL_NAME, _URL_IS_REMOTE
# 协议: git+https / git+ssh / https / file / short (org/template 视为短名 → 走 hub)
parse_url() {
    local url="$1"
    _URL_PROTO=""
    _URL_BODY=""
    _URL_NAME=""
    _URL_IS_REMOTE=0

    if [[ -z "$url" ]]; then
        echo "[FAIL] parse_url: empty url" >&2
        return 1
    fi

    case "$url" in
        git+https://*)
            _URL_PROTO="git+https"
            _URL_BODY="${url#git+https://}"
            _URL_IS_REMOTE=1
            ;;
        git+ssh://*|ssh://*)
            _URL_PROTO="git+ssh"
            _URL_BODY="${url#git+ssh://}"
            _URL_BODY="${_URL_BODY#ssh://}"
            _URL_IS_REMOTE=1
            ;;
        https://*)
            _URL_PROTO="https"
            _URL_BODY="${url#https://}"
            _URL_IS_REMOTE=1
            ;;
        file://*)
            _URL_PROTO="file"
            _URL_BODY="${url#file://}"
            _URL_IS_REMOTE=0
            ;;
        /*)
            _URL_PROTO="file"
            _URL_BODY="${url#/}"
            _URL_IS_REMOTE=0
            ;;
        *)
            # 短名 org/template → 走 hub
            _URL_PROTO="short"
            _URL_BODY="$url"
            _URL_IS_REMOTE=1
            ;;
    esac

    # 计算缓存目录名
    case "$_URL_PROTO" in
        git+https|git+ssh|https|short)
            # 用 host/path 末两段拼名字，去掉 .git
            local cleaned
            cleaned="${_URL_BODY%.git}"
            _URL_NAME=$(echo "$cleaned" | tr '/:.' '_' | sed 's/__*/_/g; s/^_//; s/_$//')
            [[ -z "$_URL_NAME" ]] && _URL_NAME="remote_template_$(date +%s)"
            ;;
        file)
            _URL_NAME=$(basename "$_URL_BODY" .json)
            [[ -z "$_URL_NAME" || "$_URL_NAME" == "/" ]] && _URL_NAME="local_template"
            ;;
    esac
    return 0
}

# 把 git+https URL 转成普通 https（git CLI 不认识 git+ 前缀）
url_to_git() {
    local url="$1"
    case "$url" in
        git+https://*) echo "https://${url#git+https://}" ;;
        git+ssh://*)   echo "ssh://${url#git+ssh://}" ;;
        *)             echo "$url" ;;
    esac
}

# 拉取/拷贝远程模板到本地缓存
# 输入: $1=url
# 输出: cache 目录路径到 stdout；并把 path 写到 _URL_CACHE_DIR 全局
# 行为:
#   - 如果缓存目录已存在 + 不强制刷新 → 直接复用（offline fallback）
#   - 否则: git clone / curl / cp
fetch_to_cache() {
    local url="$1"
    parse_url "$url" || return 1
    local target_dir="$TEMPLATE_CACHE_DIR/$_URL_NAME"
    _URL_CACHE_DIR="$target_dir"

    # 已 cache → offline fallback
    if [[ -d "$target_dir" ]]; then
        status_ok "cache hit: $target_dir (offline reuse)" >&2
        echo "$target_dir"
        return 0
    fi

    if [[ "${INIT_OFFLINE:-0}" == "1" ]]; then
        echo "[FAIL] offline mode + cache miss: $target_dir" >&2
        echo "  hint: drop --offline or pre-populate cache" >&2
        return 1
    fi

    mkdir -p "$TEMPLATE_CACHE_DIR"
    case "$_URL_PROTO" in
        git+https|git+ssh|short)
            if ! command -v git >/dev/null 2>&1; then
                echo "[FAIL] 需要 git 命令来拉 git+https/git+ssh 模板" >&2
                return 3
            fi
            local git_url
            if [[ "$_URL_PROTO" == "short" ]]; then
                git_url="https://github.com/${_URL_BODY}.git"
            else
                git_url="$(url_to_git "$url")"
            fi
            {
                init_spin_start "Cloning $git_url -> $target_dir"
                if ! git clone --depth 1 --quiet "$git_url" "$target_dir" 2>/dev/null; then
                    init_spin_stop 1
                    echo "[FAIL] git clone 失败: $git_url" >&2
                    echo "  提示: 检查网络 / SSH key (~/.ssh/id_rsa) / 协议是否支持" >&2
                    return 20
                fi
                init_spin_stop 0
                status_ok "cloned: $git_url" >&2
            } >&2
            ;;
        https)
            # 单文件 struct.json → 拉到 cache_dir/<name>/struct.json
            if ! command -v curl >/dev/null 2>&1; then
                echo "[FAIL] 需要 curl 来拉 https:// 单文件模板" >&2
                return 3
            fi
            mkdir -p "$target_dir"
            {
                init_spin_start "Downloading https://$_URL_BODY"
                if ! curl -fsSL "https://$_URL_BODY" -o "$target_dir/struct.json" 2>/dev/null; then
                    init_spin_stop 1
                    echo "[FAIL] curl 下载失败: https://$_URL_BODY" >&2
                    return 1
                fi
                init_spin_stop 0
                status_ok "downloaded: https://$_URL_BODY" >&2
            } >&2
            ;;
        file)
            if [[ ! -e "$_URL_BODY" ]]; then
                echo "[FAIL] 本地文件不存在: $_URL_BODY" >&2
                return 4
            fi
            mkdir -p "$target_dir"
            cp -R "$_URL_BODY" "$target_dir/"
            status_ok "copied local: $_URL_BODY -> $target_dir" >&2
            ;;
        *)
            echo "[FAIL] 不支持的协议: $_URL_PROTO" >&2
            return 64
            ;;
    esac

    echo "$target_dir"
}

# 在 cache 目录里找 struct.json（先 manifest.contents.struct_json，再常见名字）
find_struct_in_cache() {
    local cache_dir="$1"
    if [[ -f "$cache_dir" ]]; then
        echo "$cache_dir"; return 0
    fi
    # manifest 优先
    local mf="$cache_dir/template.manifest.json"
    local rel="struct.json"
    if [[ -f "$mf" ]]; then
        rel=$(jq -r '.contents.struct_json // "struct.json"' "$mf" 2>/dev/null || echo "struct.json")
    fi
    if [[ -f "$cache_dir/$rel" ]]; then
        echo "$cache_dir/$rel"; return 0
    fi
    # 兜底1: 目录下任意 .json（跳过 template.manifest.json）
    local found
    found=$(find "$cache_dir" -maxdepth 2 -name '*.json' -not -name 'template.manifest.json' -type f 2>/dev/null | head -1)
    if [[ -n "$found" ]]; then
        echo "$found"; return 0
    fi
    # 兜底2: 如果 cache_dir 本身只是一个文件名形式（file:// 复制后的命名），找单文件
    # file:// 模式会拷贝成 <cache_dir>/<basename>
    local single
    single=$(find "$cache_dir" -maxdepth 1 -type f ! -name 'template.manifest.json' 2>/dev/null | head -1)
    if [[ -n "$single" && -f "$single" ]]; then
        echo "$single"; return 0
    fi
    echo "[FAIL] cache 目录里找不到 struct.json: $cache_dir" >&2
    return 4
}

# ---------- imports 合并 ----------

# 深度合并两个 JSON 文件 -> 输出到第三个
# current 优先（顶层字段冲突时 current 胜出）
# modules 数组：拼接去重（同名 module 优先 current）
# components 数组：在同名 module 内拼接去重
merge_structs_deep() {
    local current="$1" incoming="$2" output="$3"
    jq -s '
        .[0] as $cur | .[1] as $inc |
        # 顶层字段：current 胜出
        $cur + (
            ($inc | with_entries(select(.key as $k | ($cur | has($k)) | not)))
        )
        # modules：拼接 + 去重（current 优先同名 module）
        | .modules = (
            (($cur.modules // []) + ($inc.modules // []))
            | unique_by(.name)
        )
        # 同名 module 内 components 拼接去重（current 优先）
        | .modules = (
            [.modules[] | . as $m |
                ([$inc.modules[]? | select(.name == $m.name) | .components // []] | flatten | unique_by(.name)) as $incoming_comps |
                .components = (($m.components // []) + $incoming_comps | unique_by(.name))
            ]
        )
    ' "$current" "$incoming" > "$output"
}

# extend: 当前 struct 优先，imports 不覆盖现有字段
merge_structs_extend() {
    local current="$1" incoming="$2" output="$3"
    # 当前字段保留；imports 仅填补缺失字段
    # 对 modules: 拼接（同名按 override_paths 处理）
    jq -s '
        .[0] as $cur | .[1] as $inc |
        $cur + (
            ($inc | with_entries(select(.key as $k | ($cur | has($k)) | not)))
        )
        | .modules = (
            (($cur.modules // []) + ($inc.modules // []))
            | unique_by(.name)
        )
    ' "$current" "$incoming" > "$output"
}

# replace: 整个替换
merge_structs_replace() {
    local incoming="$1" output="$2"
    cp "$incoming" "$output"
}

# 加载单个 import struct 到临时文件
# 支持的 import.source 形式:
#   - object 路径: "modules" / "modules[0].components"
#   - URL: 同 --from-url
# 如果 source 是 string: 直接当成 url/short name
# 如果 source 是 object: 取 .url / .source
load_import_struct() {
    local import_json="$1" idx="$2" work_dir="$3"
    local src
    src=$(echo "$import_json" | jq -r '.source // .url // empty')
    if [[ -z "$src" ]]; then
        echo "[FAIL] import[$idx] 缺少 source/url 字段" >&2
        return 1
    fi
    local cache_dir
    cache_dir=$(fetch_to_cache "$src") || return 1
    find_struct_in_cache "$cache_dir"
}

# 处理当前 struct 顶部的 imports 数组 → 输出合并后的新 struct 到 stdout
# 用法: apply_imports <struct.json>
# 注意: 所有交互输出走 stderr，stdout 只输出最终 JSON
apply_imports() {
    local base="$1"
    if ! jq -e 'has("imports") and (.imports | type == "array") and (length > 0)' "$base" >/dev/null 2>&1; then
        # 无 imports → 原样输出
        cat "$base"
        return 0
    fi

    local n_imports
    n_imports=$(jq '.imports | length' "$base")
    local i=0
    local current="$base"
    local tmpdir
    tmpdir=$(mktemp -d)
    # trap 清理
    trap 'rm -rf "$tmpdir"' RETURN

    # 进度输出全部走 stderr (FD 3 这里用不了，简单起见重定向到 stderr)
    {
        loading_dots "Resolving imports ($n_imports)" 1
    } >&2

    while [[ $i -lt $n_imports ]]; do
        local import_item
        import_item=$(jq -c ".imports[$i]" "$current")
        local strategy
        strategy=$(echo "$import_item" | jq -r '.merge_strategy // "deep_merge"')
        local src_display
        src_display=$(echo "$import_item" | jq -r '.source // .url // "(no source)"')
        local as_module
        as_module=$(echo "$import_item" | jq -r '.as_module // empty')

        {
            box_draw "Importing [$((i+1))/$n_imports]" "source: $src_display
strategy: $strategy"
        } >&2

        # 把 import_item 转成一个临时 struct.json，as_module 时包成 module
        local import_struct
        import_struct="$tmpdir/import_${i}.json"
        local cache_struct
        cache_struct=$(load_import_struct "$import_item" "$i" "$tmpdir") || return 1

        if [[ -n "$as_module" ]]; then
            jq --arg name "$as_module" '{modules: [{name: $name, components: [.modules[]?.components[]? // empty]}]}' \
                "$cache_struct" > "$import_struct" 2>/dev/null || cp "$cache_struct" "$import_struct"
        else
            cp "$cache_struct" "$import_struct"
        fi

        # 应用 override_paths: 当前 struct 对 override_paths 指向的字段保持不变
        local override_paths
        override_paths=$(echo "$import_item" | jq -r '.override_paths // [] | .[]' 2>/dev/null)
        local next="$tmpdir/merged_${i}.json"

        case "$strategy" in
            deep_merge)
                merge_structs_deep "$current" "$import_struct" "$next"
                ;;
            extend)
                merge_structs_extend "$current" "$import_struct" "$next"
                ;;
            replace)
                merge_structs_replace "$import_struct" "$next"
                ;;
            *)
                echo "[FAIL] 未知 merge_strategy: $strategy" >&2
                return 1
                ;;
        esac

        status_ok "merged import $((i+1)) via $strategy" >&2
        current="$next"
        i=$((i+1))
    done

    cat "$current"
}

# ---------- v9 P0: 模式 3：--from-url <url> ----------
run_from_url_mode() {
    local url="$1"

    echo ""
    echo "============================================================"
    echo " bootstrap init --from-url"
    echo "============================================================"
    echo "  url    : $url"
    echo "  cache  : $TEMPLATE_CACHE_DIR"
    echo "  output : $OUTPUT_DIR"
    echo "============================================================"
    echo ""

    loading_dots "Cloning from $url" 1

    # 1. 拉取/解析 URL
    local cache_dir
    cache_dir=$(fetch_to_cache "$url") || exit 1

    # 2. 找 struct.json
    local struct_src
    struct_src=$(find_struct_in_cache "$cache_dir") || exit 4
    status_ok "struct source: $struct_src"

    # 3. AI 模式：manifest 的 prompts 全部走 default
    local manifest_path=""
    if [[ -f "$cache_dir/template.manifest.json" ]]; then
        manifest_path="$cache_dir/template.manifest.json"
    fi
    if [[ -n "$manifest_path" ]]; then
        local np
        np=$(jq -r '.prompts // [] | length' "$manifest_path")
        [[ "$np" -gt 0 ]] && status_info "AI mode: applying $np prompt defaults (no interaction)"
    fi

    # 4. 应用 imports 合并
    {
        loading_dots "Resolving imports" 1
    } >&2
    local merged
    merged=$(apply_imports "$struct_src") || {
        echo "[FAIL] imports 合并失败" >&2
        exit 1
    }

    # 5. 输出到目标目录
    mkdir -p "$OUTPUT_DIR"
    local target="$OUTPUT_DIR/struct.json"
    if [[ -f "$target" ]]; then
        if [[ ! -t 0 ]]; then
            echo "[FAIL] struct.json 已存在且非交互: $target" >&2
            exit 10
        fi
        echo -n "struct.json 已存在，覆盖？ [y/N]: "
        read -r ans || true
        [[ "$ans" =~ ^[Yy]$ ]] || { echo "  取消"; exit 0; }
    fi

    init_spin_start "Writing $target"
    echo "$merged" > "$target"
    init_spin_stop $?

    # 6. emit 基础设施
    emit_gitignore "$OUTPUT_DIR"
    emit_gitattributes "$OUTPUT_DIR"
    emit_githooks "$OUTPUT_DIR"

    # 7. 写 .bootstrap/state.json
    mkdir -p "$OUTPUT_DIR/.bootstrap"
    local state_file="$OUTPUT_DIR/.bootstrap/state.json"
    local now
    now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    local struct_hash
    struct_hash=$(sha256sum "$target" | awk '{print $1}')
    jq -n \
        --arg schema_v "1.0" \
        --arg at "$now" \
        --arg version "0.9.0" \
        --arg url "$url" \
        --arg user "${USER:-unknown}@${HOSTNAME:-localhost}" \
        --arg hash "$struct_hash" \
        '{
            schema_version: $schema_v,
            last_run: {
                at: $at,
                version: $version,
                command: "init",
                argv: ["init", "--from-url", $url],
                exit_code: 0,
                duration_ms: 0,
                user: $user
            },
            struct_hash: $hash,
            struct_hash_history: [
                { at: $at, hash: $hash, reason: ("init --from-url " + $url) }
            ],
            stats: { generators_run: 0, files_written: 0, bytes_written: 0 },
            errors: []
        }' > "$state_file"
    status_ok ".bootstrap/state.json"

    # 8. 汇总
    local bytes
    bytes=$(wc -c < "$target")
    local tokens=$(( bytes / 4 ))
    token_counter "$tokens" "in this struct.json"
    echo ""
    status_ok "from-url scaffolded: $url"
    echo "  cache: $cache_dir"
    echo "  target: $target"

    milestone "Project scaffolded from $url"
}

# ---------- 调度 ----------
if [[ -n "$FROM_URL" ]]; then
    run_from_url_mode "$FROM_URL"
elif [[ -n "$FROM_FILE" ]]; then
    run_from_mode "$FROM_FILE"
elif [[ -n "$TEMPLATE_NAME" ]]; then
    run_template_mode "$TEMPLATE_NAME"
else
    list_templates
    # list_templates 里如果选了模板，会重新设置 TEMPLATE_NAME 或 FROM_FILE
    if [[ -n "$FROM_FILE" ]]; then
        run_from_mode "$FROM_FILE"
    elif [[ -n "$TEMPLATE_NAME" ]]; then
        run_template_mode "$TEMPLATE_NAME"
    fi
fi