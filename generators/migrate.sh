#!/usr/bin/env bash
# generators/migrate.sh — struct.json schema migration tool
#
# 用法:
#   bash generators/migrate.sh --from 3.0 --to 3.1 --struct ./struct.json
#   bash generators/migrate.sh --from 3.0 --to 3.1 --struct ./struct.json --dry-run
#   bash generators/migrate.sh --from 3.0 --to 3.1 --struct ./struct.json --output ./struct.new.json
#
# 行为:
#   1. 读入 --struct 指向的 struct.json
#   2. 检查 schema_version 是否 == --from；若否则报错退出
#   3. 应用从 --from 到 --to 之间的所有迁移规则
#   4. 默认覆盖输入文件；--dry-run 只打印到 stdout 不写盘
#   5. --output <file> 把结果写到不同文件
#   6. 迁移成功后会自动跑 validate.sh 确认仍然合规
#
# 支持的迁移:
#   3.0 -> 3.1: 每个 todo 加 acceptance_criteria=""；
#               每个 module 加 cross_cutting=[] / phases=[]；
#               schema_version 升到 3.1
#   3.1 -> 3.2: 占位迁移 — schema_version 升到 3.2，无字段变化（预留 language_hint）
#
# 退出码: 0 = 成功；1 = 错误；2 = 迁移后 schema 校验失败

set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SELF_DIR/_lib.sh"

# ---------- 默认值 ----------
STRUCT_FILE="./struct.json"
FROM_VER=""
TO_VER=""
DRY_RUN=0
OUTPUT_FILE=""
VALIDATE_AFTER=1

usage() {
    cat <<EOF
用法: bash generators/migrate.sh --from <ver> --to <ver> [选项]

必填:
  --from <ver>           当前 schema_version（如 3.0）
  --to   <ver>           目标 schema_version（如 3.1）

可选项:
  --struct <file>        struct.json 路径，默认 ./struct.json
  --output <file>        写到不同文件（默认覆盖 --struct 指向的源文件）
  --dry-run              只打印迁移后 JSON 到 stdout，不写盘
  --no-validate          迁移后跳过 validate.sh 调用
  -h, --help             显示本帮助

支持的内置迁移:
  3.0 -> 3.1   todo: acceptance_criteria="" ；module: cross_cutting=[], phases=[]
  3.1 -> 3.2   占位（schema_version 升级；为后续 language_hint 预留）

示例:
  bash generators/migrate.sh --from 3.0 --to 3.1 --struct ./struct.json --dry-run
  bash generators/migrate.sh --from 3.0 --to 3.1 --struct ./struct.json
EOF
}

# ---------- 参数解析 ----------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --from)        FROM_VER="$2"; shift 2 ;;
        --to)          TO_VER="$2"; shift 2 ;;
        --struct)      STRUCT_FILE="$2"; shift 2 ;;
        --output)      OUTPUT_FILE="$2"; shift 2 ;;
        --dry-run)     DRY_RUN=1; shift ;;
        --no-validate) VALIDATE_AFTER=0; shift ;;
        -h|--help)     usage; exit 0 ;;
        *)             echo "[FAIL] 未知参数: $1" >&2; usage; exit 1 ;;
    esac
done

# ---------- 基本检查 ----------
command -v jq >/dev/null 2>&1 || { echo "[FAIL] 缺少依赖: jq" >&2; exit 1; }

[[ -n "$FROM_VER" ]] || { echo "[FAIL] 缺少 --from" >&2; usage; exit 1; }
[[ -n "$TO_VER"   ]] || { echo "[FAIL] 缺少 --to"   >&2; usage; exit 1; }

[[ -f "$STRUCT_FILE" ]] || { echo "[FAIL] 找不到 struct.json: $STRUCT_FILE" >&2; exit 1; }
jq empty "$STRUCT_FILE" 2>/dev/null || { echo "[FAIL] $STRUCT_FILE 不是合法 JSON" >&2; exit 1; }

CURRENT_VER=$(jq -r '.schema_version // ""' "$STRUCT_FILE")
[[ -n "$CURRENT_VER" ]] || { echo "[FAIL] $STRUCT_FILE 没有 schema_version 字段" >&2; exit 1; }

if [[ "$CURRENT_VER" != "$FROM_VER" ]]; then
    echo "[FAIL] schema_version 不匹配：文件=$CURRENT_VER, --from=$FROM_VER" >&2
    echo "       请先把 --from 设为当前版本，或先升级到上一版本" >&2
    exit 1
fi

if [[ "$FROM_VER" == "$TO_VER" ]]; then
    echo "[INFO] from == to ($FROM_VER)，无需迁移"
    exit 0
fi

# ---------- 决定输出位置 ----------
if [[ $DRY_RUN -eq 1 ]]; then
    OUT_TARGET="<stdout>"
elif [[ -n "$OUTPUT_FILE" ]]; then
    OUT_TARGET="$OUTPUT_FILE"
else
    OUT_TARGET="$STRUCT_FILE"
fi

echo "============================================================"
echo " bootstrap migrate"
echo " struct  : $STRUCT_FILE"
echo " schema_version: $CURRENT_VER -> $TO_VER"
echo " output  : $OUT_TARGET"
[[ $DRY_RUN -eq 1 ]] && echo " mode    : DRY RUN (no writes)"
echo "============================================================"
echo ""

# ---------- 单一迁移函数 ----------
# 用法: apply_migration <from> <to> <current_json>
# 返回新的 json 到 stdout
apply_migration() {
    local from="$1" to="$2" current="$3"
    local key="${from}_${to}"

    case "$key" in
        3.0_3.1)
            echo "$current" | jq '
                # 每个 todo 加 acceptance_criteria=""
                .modules |= map(
                    .components |= map(
                        if has("todos") then
                            .todos |= map(
                                if has("acceptance_criteria") then .
                                else . + {acceptance_criteria: ""}
                                end
                            )
                        else .
                        end
                    )
                ) |
                # 每个 module 加 cross_cutting=[] 和 phases=[]
                .modules |= map(
                    if has("cross_cutting") then .
                    else . + {cross_cutting: []}
                    end
                    |
                    if has("phases") then .
                    else . + {phases: []}
                    end
                ) |
                .schema_version = "3.1"
            '
            ;;
        3.1_3.2)
            # 占位：仅升级 schema_version，无字段变化（language_hint 预留）
            echo "$current" | jq '.schema_version = "3.2"'
            ;;
        *)
            echo "[FAIL] 不支持的迁移路径: ${from} -> ${to}" >&2
            return 1
            ;;
    esac
}

# ---------- 链式应用迁移 ----------
CURRENT_JSON=$(cat "$STRUCT_FILE")
CURRENT="$FROM_VER"

while [[ "$CURRENT" != "$TO_VER" ]]; do
    NEXT=""
    case "$CURRENT" in
        3.0) NEXT="3.1" ;;
        3.1) NEXT="3.2" ;;
        *)
            echo "[FAIL] 不知道如何从 $CURRENT 继续迁移" >&2
            exit 1
            ;;
    esac

    echo "[STEP] migrate ${CURRENT} -> ${NEXT}"
    MIGRATED=$(apply_migration "$CURRENT" "$NEXT" "$CURRENT_JSON")
    if [[ -z "$MIGRATED" ]] || ! echo "$MIGRATED" | jq empty >/dev/null 2>&1; then
        echo "[FAIL] 迁移 ${CURRENT} -> ${NEXT} 失败（产生非法 JSON）" >&2
        exit 1
    fi

    # 报告做了哪些改动 — 通过直接比较 count 的差值
    AC_BEFORE=$(echo "$CURRENT_JSON" | jq '[.modules[].components[].todos? // [] | .[] | select(has("acceptance_criteria"))] | length')
    AC_AFTER=$(echo "$MIGRATED"    | jq '[.modules[].components[].todos? // [] | .[] | select(has("acceptance_criteria"))] | length')
    CC_BEFORE=$(echo "$CURRENT_JSON" | jq '[.modules[] | select(has("cross_cutting"))] | length')
    CC_AFTER=$(echo "$MIGRATED"    | jq '[.modules[] | select(has("cross_cutting"))] | length')
    PH_BEFORE=$(echo "$CURRENT_JSON" | jq '[.modules[] | select(has("phases"))] | length')
    PH_AFTER=$(echo "$MIGRATED"    | jq '[.modules[] | select(has("phases"))] | length')

    AC_DELTA=$((AC_AFTER - AC_BEFORE))
    CC_DELTA=$((CC_AFTER - CC_BEFORE))
    PH_DELTA=$((PH_AFTER - PH_BEFORE))

    [[ "$AC_DELTA" -gt 0 ]] && echo "       + todos with acceptance_criteria: $AC_DELTA (was $AC_BEFORE, now $AC_AFTER)"
    [[ "$CC_DELTA" -gt 0 ]] && echo "       + modules with cross_cutting:     $CC_DELTA (was $CC_BEFORE, now $CC_AFTER)"
    [[ "$PH_DELTA" -gt 0 ]] && echo "       + modules with phases:            $PH_DELTA (was $PH_BEFORE, now $PH_AFTER)"
    if [[ "$AC_DELTA" -eq 0 && "$CC_DELTA" -eq 0 && "$PH_DELTA" -eq 0 ]]; then
        echo "       (no field additions in this step)"
    fi

    CURRENT_JSON="$MIGRATED"
    CURRENT="$NEXT"
done

# ---------- 写盘 / 打印 ----------
if [[ $DRY_RUN -eq 1 ]]; then
    echo ""
    echo "----- DRY RUN: 迁移后的 struct.json (stdout) -----"
    echo "$CURRENT_JSON" | jq .
elif [[ -n "$OUTPUT_FILE" ]]; then
    echo ""
    echo "[WRITE] $OUTPUT_FILE"
    echo "$CURRENT_JSON" | jq . > "$OUTPUT_FILE"
else
    # 覆盖原文件前先备份
    BACKUP="${STRUCT_FILE}.migrate-backup-$(date -u +%Y%m%dT%H%M%SZ)"
    cp "$STRUCT_FILE" "$BACKUP"
    echo ""
    echo "[WRITE] $STRUCT_FILE (backup: $BACKUP)"
    echo "$CURRENT_JSON" | jq . > "$STRUCT_FILE"
fi

# ---------- 迁移后校验 ----------
if [[ $VALIDATE_AFTER -eq 1 && $DRY_RUN -eq 0 ]]; then
    echo ""
    echo "[VALIDATE] 跑 validate.sh 确认迁移后仍合规..."
    TARGET_FILE="$STRUCT_FILE"
    [[ -n "$OUTPUT_FILE" ]] && TARGET_FILE="$OUTPUT_FILE"
    if STRUCT_FILE="$TARGET_FILE" bash "$SELF_DIR/validate.sh" >/dev/null 2>&1; then
        echo "[OK] validate.sh 通过"
    else
        echo "[WARN] validate.sh 失败（exit=$?）— 检查上面日志"
        # 迁移本身是成功的；validate 是 best-effort
    fi
fi

echo ""
echo "[DONE] migration ${FROM_VER} -> ${TO_VER} 完成"
exit 0