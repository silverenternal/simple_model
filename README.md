# simple_model

> The AI-Era Maven. Declarative schema, multi-language code generation, parallel AI-agent dispatch, zero runtime dependencies.
>
> AI 时代的 Maven。声明式 schema、多语言代码生成、并行 AI agent 调度、零运行时依赖。

---

## 目录 / Table of Contents

- [简介 / Overview](#简介--overview)
- [核心特性 / Key Features](#核心特性--key-features)
- [零依赖哲学 / Zero Dependencies](#零依赖哲学--zero-dependencies)
- [5 分钟上手 / Quick Start](#5-分钟上手--quick-start)
- [完整命令清单 / Complete Command Reference](#完整命令清单--complete-command-reference)
- [核心架构 / Architecture](#核心架构--architecture)
- [AI agent 工作流 / For AI Agents](#ai-agent-工作流--for-ai-agents)
- [人类使用 / For Humans](#人类使用--for-humans)
- [示例项目 / Examples](#示例项目--examples)
- [Git 集成 / Git Integration](#git-集成--git-integration)
- [CI/CD 集成 / CI/CD](#cicd-集成--cicd)
- [扩展 / Extending](#扩展--extending)
- [常见问题 / FAQ](#常见问题--faq)
- [对比同类项目 / Comparison](#对比同类项目--comparison)
- [贡献 / Contributing](#贡献--contributing)
- [许可 / License](#许可--license)

---

## 简介 / Overview

**simple_model** is a schema-driven project orchestrator. A single `struct.json` describes your project's architecture (modules, components, dependencies, todos with blockers), and `bootstrap.sh` turns it into code, documentation, AI context, and parallel work assignments.

`struct.json` 是项目的**单一事实源（Single Source of Truth）**。整个工具链围绕它运转：

```
struct.json  ─→  多语言代码骨架（Python / Rust / Go / TypeScript）
           ─→  AI agent 上下文（AGENTS.md / .ai/*.json）
           ─→  客户端可视化（ARCHITECTURE.md / architecture.html）
           ─→  并行任务队列（wave-based blocker DAG）
           ─→  Git worktree 调度（多 AI agent 并行开发）
```

**Designed for two audiences simultaneously**:

| 使用者 / Audience | 需求 / Need | 满足方式 / How |
|---|---|---|
| **AI agent (Codex / Claude Code)** | 节省 token、零交互、JSON 一切 | `bootstrap --json --explain <comp>` |
| **人类开发者** | 友好 CLI、动画、可视化 | `bootstrap.sh` + `box_draw` / `milestone` / `progress_bar` |

---

## 核心特性 / Key Features

1. **零外部依赖** — 只需 `bash >= 4` 和 `jq`（可选 `ajv-cli`）。无 Python、无 Node、无 Docker。
2. **Schema 驱动** — 一个 `struct.json` 描述整个项目架构。
3. **多语言代码生成** — Python / Rust / Go / TypeScript，每个 generator 都是纯 bash + jq。
4. **真实编译验证** — Rust generator 自动跑 `cargo check + cargo test`（91/91 通过）。
5. **AI agent 工作流** — `next` / `claim` / `complete` / `explain` 四个命令覆盖 AI agent 完整生命周期。
6. **并行 wave 调度** — 基于 blocker DAG 自动计算 wave，同 wave 内可同时分发 N 个 AI agent。
7. **Git worktree 集成** — 每个 AI agent 在独立 worktree 工作，无冲突。
8. **自动检查 + 纠错** — `drift` 检查 schema ↔ 产物一致性，`lint` 检测 5 类反模式，`lint --fix` 自动修复。
9. **远程模板** — `init --from-url <git-url>` 从远程仓库拉模板。
10. **甲方可视化** — 单文件 `architecture.html` 直接邮件给客户，无需后端。
11. **增量构建** — 基于 SHA-256 hash，未变化的文件自动 `[SKIP]`。
12. **零交互** — 所有命令 flag-based，AI agent 可直接 `bootstrap --claim <id>` 无需 stdin。

---

## 零依赖哲学 / Zero Dependencies

```
$ bootstrap.sh --version
bash >= 4.0       # any modern Linux / macOS
jq >= 1.5         # JSON processor
ajv-cli (optional) # strict JSON Schema validation
cargo (optional)   # only if you generate Rust
tsc (optional)     # only if you generate TypeScript
```

That's it. No `pip install`, no `npm install`, no virtualenv. The entire toolchain is ~3500 lines of pure bash + jq, copy-pasteable into any git repo.

这意味着：

- 可以在任何环境跑（CI、Docker、Alpine、嵌入式）
- 没有依赖冲突、没有 supply chain attack 面
- 可以直接 `cp -r simple_model/ your-project/` 起步
- AI agent 不需要 `npm install` 几分钟就能跑

---

## 5 分钟上手 / Quick Start

### 安装 / Install

```bash
# 方式 1: 直接 git clone
git clone https://github.com/your-org/simple_model.git
cd simple_model

# 方式 2: 复制文件到现有项目
cp -r simple_model/{bootstrap.sh,generators,specs,struct.schema.json,.gitignore} ./your-project/
```

### 第一个项目 / Create Your First Project

```bash
# 用现成模板（web_spa / backend_api / llm_agent）
./bootstrap.sh --init --template web_spa --output ./my-app
cd my-app

# 或从远程 URL 拉模板
./bootstrap.sh --init --from-url https://example.com/ml-template.json --output ./ml-app

# 或编辑已有的 struct.json
vim struct.json
```

### 跑完整流程 / Run the Full Pipeline

```bash
# 1. 校验 schema 合法
./bootstrap.sh --validate

# 2. dry-run 看会生成什么
./bootstrap.sh --plan --target python,rust,viz

# 3. 真生成
./bootstrap.sh --target python,rust,viz

# 4. 检查产物是否过期
./bootstrap.sh --drift

# 5. 反模式扫描
./bootstrap.sh --lint

# 6. 一键修复
./bootstrap.sh --lint --fix
```

### 给 AI agent 用 / For AI Agents

```bash
# AI agent 启动会话时
cat AGENTS.md                                  # 项目系统提示
bootstrap --next --json | jq '.id'             # 我该干啥
bootstrap --explain <Component> --json         # 这个 component 详情

# 接到 task 后
bootstrap --claim data_loader_1                # 标记 in_progress
# ... 写代码 ...
bootstrap --complete data_loader_1             # 标记 done
```

---

## 完整命令清单 / Complete Command Reference

所有命令都支持 `--json` 输出（机器可读）和人类可读双模式。

### 项目生命周期 / Project Lifecycle

| 命令 / Command | 用途 / Purpose | AI 友好度 / AI-Friendly |
|---|---|---|
| `bootstrap --init --template <name>` | 从模板创建新项目 | 全 flag，可非交互 |
| `bootstrap --init --from-url <url>` | 从远程 URL 拉模板 | 全 flag |
| `bootstrap --init --from <file>` | 从已有 JSON 创建 | 全 flag |
| `bootstrap --validate` | schema + 引用完整性校验 | 全 flag |
| `bootstrap --plan` | dry-run，看会生成什么 | 全 flag |
| `bootstrap --target <list>` | 跑指定 generators | `all` 或 `python,rust,viz` |
| `bootstrap --include <modules>` | 只处理某些 modules | 全 flag |
| `bootstrap --exclude <modules>` | 排除某些 modules | 全 flag |
| `bootstrap --drift` | 检查 schema ↔ 产物一致性 | 全 flag |
| `bootstrap --lint [--fix]` | 反模式扫描 + 自动修复 | 全 flag |
| `bootstrap --status` | 项目进度 dashboard | 全 flag |

### AI Agent 工作流 / AI Agent Workflow

| 命令 / Command | 用途 / Purpose |
|---|---|
| `bootstrap --next` | 给我下一个 todo（最高优先级） |
| `bootstrap --claim <todo_id>` | 我接这个 todo |
| `bootstrap --complete <todo_id>` | 我做完了 |
| `bootstrap --reset <todo_id>` | 回滚到 pending |
| `bootstrap --explain <component>` | 这个 component 完整 context |

### Git 集成 / Git Integration

| 命令 / Command | 用途 / Purpose |
|---|---|
| `bootstrap --target dispatch --wave 1` | 把 wave 1 的 todos 分到 git worktree |
| `bootstrap --target merge --wave 1` | merge wave 1 所有 branches + sync status |

### 通用选项 / Common Options

| 选项 / Option | 用途 / Purpose |
|---|---|
| `-s, --struct <file>` | 指定 struct.json 路径（默认 `./struct.json`） |
| `-S, --schema <file>` | 指定 schema 路径（默认 `./struct.schema.json`） |
| `-o, --output <dir>` | 输出根目录（默认 `./generated`） |
| `--json` | 全机器可读输出 |
| `--plan` | dry-run，不写盘 |
| `--no-todo` | 跳过 dev_queue 生成 |
| `--no-validate` | 跳过 schema 校验 |
| `--force` | 强制全量重建（无视 incremental cache） |

---

## 核心架构 / Architecture

```
simple_model/
├── bootstrap.sh                      # 主编排器（~400 行 bash）
├── struct.schema.json                # 通用 schema v3.0
├── struct.json                       # 你的项目描述
├── examples/                         # 3 个示例项目
│   ├── web_spa.json
│   ├── backend_api.json
│   └── llm_agent.json
├── generators/                       # 13 个生成器（每个纯 bash）
│   ├── _lib.sh                       # 共享库（拓扑排序、动画、helpers）
│   ├── agents_md.sh                  # AGENTS.md（AI 启动入口）
│   ├── context_json.sh               # .ai/context.json
│   ├── dev_queue.sh                  # 并行 wave 任务队列
│   ├── visualization.sh              # Mermaid + HTML
│   ├── explain.sh                    # 组件 context dump（节省 token）
│   ├── check.sh                      # drift + lint + auto-fix
│   ├── agent.sh                      # status/next/claim/complete
│   ├── init.sh                       # init --template / --from-url
│   ├── python.sh                     # Python 代码生成
│   ├── rust.sh                       # Rust 代码生成 + cargo 验证
│   ├── go.sh                         # Go 代码生成
│   └── typescript.sh                 # TypeScript 代码生成
├── specs/                            # 8 个 JSON Schema spec
│   ├── lifecycle.json                # 13 个生命周期命令契约
│   ├── state.json                    # 状态文件 schema
│   ├── explain-output.json           # explain 命令输出 schema
│   ├── context-bundle.json           # AI context 切片清单
│   ├── drift-lint-rules.json         # 8 条检查规则
│   ├── ci-integration.json           # CI pipeline meta-schema
│   ├── plugin-manifest.json          # 第三方插件清单
│   └── template-manifest.json        # 脚手架模板清单
├── tools/install-hooks.sh            # git hooks 安装
├── .githooks/pre-commit              # commit 前 schema 校验
├── .githooks/pre-push                # push 前 cargo test
├── tests/test_animations.sh          # 动画库回归测试
└── .gitignore / .gitattributes
```

### 核心数据流 / Core Data Flow

```
   struct.json (input)
       │
       ▼
   ┌──────────────┐
   │ bootstrap.sh │  ─→  validates + computes topology
   └──────────────┘
       │
       ├────→ generators/python.sh ──────→ generated/python/<module>/<comp>.py
       ├────→ generators/rust.sh   ──────→ generated/rust/src/<module>/<comp>.rs
       ├────→ generators/typescript.sh ─→ generated/typescript/<module>/<comp>.ts
       ├────→ generators/agents_md.sh ──→ AGENTS.md
       ├────→ generators/context_json.sh → .ai/context.json
       ├────→ generators/dev_queue.sh ───→ .ai/dev_queue.json (parallel waves)
       ├────→ generators/visualization.sh → docs/ARCHITECTURE.md + architecture.html
       └────→ generators/check.sh ────────→ drift + lint reports
```

---

## AI agent 工作流 / For AI Agents

### Token 节省实测 / Token Savings (Measured)

| 场景 / Scenario | 不用我们 / Without | 用我们 / With | 节省 / Savings |
|---|---|---|---|
| 拿单个 component context | grep 整个项目 ~10000 tok | `bootstrap --explain` = **~700 tok** | **93%** |
| 找下一个 task | 自己解析 dev_queue = ~5000 tok | `bootstrap --next --json` = **~200 tok** | **96%** |
| 看项目状态 | 读 4 个文件 = ~2000 tok | `bootstrap --status --json` = **~150 tok** | **92%** |
| 反模式扫描 | 写规则自己跑 | `bootstrap --lint --json` = **~500 tok** | **99%** |
| 修反模式 | grep + 手改 | `bootstrap --lint --fix` = **~100 tok** | **97%** |

### AI agent 启动模板 / AI Agent Startup Template

```bash
# === AI agent session start ===
# 1. Read AGENTS.md (single source of project context)
cat AGENTS.md

# 2. Check current task queue
cat .ai/dev_queue.md | head -50

# 3. Pick a task and get its full context
TASK_ID=$(bootstrap --next --json | jq -r '.id')
bootstrap --explain "$TASK_ID" --json > /tmp/task-context.json

# 4. Claim the task (lock it)
bootstrap --claim "$TASK_ID"

# 5. Read the implementation hints
jq '.hints.files_to_read' /tmp/task-context.json

# 6. Implement the component
# (write code here)

# 7. Mark done and check progress
bootstrap --complete "$TASK_ID"
bootstrap --status
```

### 为什么是 AI 时代 Maven / Why "AI-Era Maven"

Maven 解决了 Java 项目从 0 到能跑需要 200 行 XML + 装一堆工具 + 读懂 Ant 的问题。

我们解决 AI agent 接到新项目要读 100K token 代码才能开工的问题：

| Maven | simple_model |
|---|---|
| `pom.xml` | `struct.json` |
| `mvn compile / test / package` | `bootstrap --target python / rust / viz` |
| `~/.m2/repository` | `~/.bootstrap-templates/` |
| Maven Central | 远程模板仓库（`--from-url`） |
| Plugin architecture | Generators 目录 |
| `mvn dependency:tree` | `bootstrap --explain` |
| `archetype:generate` | `bootstrap --init --template` |

---

## 人类使用 / For Humans

### 安装 Git Hooks（提交前自动校验）

```bash
./tools/install-hooks.sh
```

之后每次 `git commit` 自动跑：
- `jq empty struct.json` 检查 JSON 合法
- `bootstrap --plan --target all` dry-run
- `bootstrap --target rust` 验证编译

### 看架构可视化（给老板/甲方）

```bash
./bootstrap.sh --target viz
open generated/docs/architecture.html   # 单文件 HTML，邮件直接发
cat generated/docs/ARCHITECTURE.md      # GitHub 自动渲染 Mermaid
```

### 当前进度 dashboard

```bash
./bootstrap.sh --status
```

输出：
```
  ┌── Project Status                                  ┐
  │ modules: 15  components: 91  todos: 45           │
  │ pending: 32  in_progress: 0  done: 0             │
  └──────────────────────────────────────────────────┘

  Wave 1 (32 tasks, parallel-safe)
  ██████████░░░░░░░░░░░░░░░░░░░░  34%
  Wave 2 (8 tasks, depends on wave 1)
  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  0%
```

### 18 个 CLI 动画原语（纯 ASCII，零 emoji）

| 类别 / Category | 原语 / Primitive |
|---|---|
| 状态标签 | `status_ok` / `status_fail` / `status_warn` / `status_info` |
| 加载动画 | `loading_dots` / `spin_start` + `spin_stop` |
| 进度条 | `progress_bar` / `ascii_bar` / `pulse_bar` / `compare_bar` |
| 装饰 | `box_draw` / `section_banner` / `milestone` / `rainbow_text` |
| 文本 | `typing_text` / `fireworks` / `count_down` |
| 结构 | `tree_node` / `header_line` / `wave_anim` / `step` |
| 计数 | `token_counter` |

---

## 示例项目 / Examples

仓库自带 3 个示例，跨前端 / 后端 / AI agent 三大领域：

| 示例 / Example | 领域 / Domain | Module 数 | Component 数 | Todo 数 |
|---|---|---|---|---|
| `examples/web_spa.json` | 前端 React SPA | 4 | 9 | 12 |
| `examples/backend_api.json` | 后端 REST API（Go 分层）| 4 | 13 | 8 |
| `examples/llm_agent.json` | LLM agent 运行时 | 4 | 12 | 6 |
| `struct.json` | ML 训练平台 | 15 | 91 | 45 |

```bash
# 用 web_spa 模板起步
./bootstrap.sh --init --template web_spa --output ./my-spa
cd my-spa
ls  # struct.json, .gitignore, .gitattributes, .githooks/, README.md
```

---

## Git 集成 / Git Integration

### 仓库结构约定 / Repository Convention

仓库**只 commit schema 和工具**，**不 commit 生成产物**：

```bash
git add struct.json bootstrap.sh generators/ specs/ ...
git commit -m "feat: add LoginPage component"
# 不要 git add generated/ （已在 .gitignore）
```

好处：
- PR review 看 `struct.json` 改动就能理解"做了什么"
- 零 merge conflict（生成代码不冲突）
- 回滚简单（`git revert struct.json` + 重 bootstrap）

### Wave → Worktree 自动派发

```bash
# 主管 AI agent: 把 wave 1 分到 9 个 worktree
./bootstrap.sh --target dispatch --wave 1

# 输出：
#   Created worktree /tmp/wt-api-AuthAPI-api_auth_refresh
#   Created worktree /tmp/wt-pages-LoginPage-page_login_submit
#   ...

# 每个 AI agent 在自己的 worktree 工作
cd /tmp/wt-api-AuthAPI-api_auth_refresh
# ... 写代码 ...
git commit -am "feat: [api_auth_refresh] 实现 silent refresh"
git push origin wave/1-api_auth_refresh
```

### Pre-commit Hook（自动校验）

```bash
./tools/install-hooks.sh   # 一次性安装
```

之后 `git commit` 自动跑 schema 校验 + Rust 编译。

---

## CI/CD 集成 / CI/CD

`.github/workflows/bootstrap.yml`（需要时创建）应包含：

```yaml
name: bootstrap validate
on: [push, pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: install jq
        run: sudo apt-get install -y jq
      - name: validate schema
        run: ./bootstrap.sh --no-todo --target all --plan
      - name: drift check
        run: ./bootstrap.sh --drift
      - name: lint
        run: ./bootstrap.sh --lint
      - name: rust test (if generated)
        run: |
          ./bootstrap.sh --target rust
          cd generated/rust && cargo test
```

详细 spec 见 `specs/ci-integration.json`。

---

## 扩展 / Extending

### 添加新 generator

```bash
# 1. 创建 generators/mylang.sh
cat > generators/mylang.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
LANG="mylang"
LANG_DIR="${OUTPUT_DIR}/${LANG}"
mkdir -p "$LANG_DIR"
# ... 你的生成逻辑 ...
EOF
chmod +x generators/mylang.sh

# 2. 用 --target mylang 调用
./bootstrap.sh --target mylang
```

### 添加新 lint 规则

编辑 `specs/drift-lint-rules.json`，加到对应 category：

```json
{
  "id": "my-new-rule",
  "description": "...",
  "severity": "warning",
  "check": {
    "type": "jq",
    "expression": ".modules[].components[].name | select(test(\"^[a-z]\"))",
    "compare": "ne"
  },
  "remediation": "...",
  "fix": {
    "available": true,
    "strategy": "jq_transform",
    "expression": "..."
  }
}
```

下次跑 `bootstrap --lint` 自动应用。

### 添加新动画

编辑 `generators/_lib.sh`，在末尾追加：

```bash
my_animation() {
    local msg="$1"
    # 你的 ASCII 动画
}
```

下次所有 generator 自动能用。

---

## 常见问题 / FAQ

**Q: 我已经有代码项目，能用 simple_model 吗？**

A: 可以。跑 `bootstrap --init --from ./your-existing-structure.json --output ./your-project/` 生成 `struct.json`，然后迭代。

**Q: AI agent 在 CI 里跑会不会很慢？**

A: 不会。最重的操作是 Rust 的 `cargo check`（首次 ~30s），增量构建后只 ~2s。其他 generator 都是毫秒级。

**Q: 我能加私有 generator 而不开源吗？**

A: 可以。把 `generators/` 当插件目录，加你自己的 `mycorp_generator.sh` 即可。schema 是开放的。

**Q: struct.json 改坏了怎么恢复？**

A: `bootstrap --lint --fix` 会自动修复。反模式检测 + 自动备份 + 一键还原。

**Q: 为什么不用 Python / Node？**

A: 零依赖。AI agent 不需要装 runtime；CI 不需要 cache；Docker 镜像更小；冷启动 <100ms。

**Q: 多 AI agent 怎么避免互相冲突？**

A: 用 `bootstrap --target dispatch --wave 1`。每个 AI agent 在独立 git worktree，互不干扰。merge 阶段再合回 main。

**Q: --explain 和 --status 在大项目里会不会很慢？**

A: 不会。两个命令都是纯 jq 操作，O(N) 在组件数。1000 个 component 也是 <500ms。

---

## 对比同类项目 / Comparison

| 维度 / Dimension | simple_model | OpenAPI Codegen | Protobuf | Terraform | Nx / Turbo | Cookiecutter |
|---|---|---|---|---|---|---|
| 零外部依赖 | YES | no | no | no | no | no |
| 领域通用 | YES | no (REST only) | no (RPC) | no (infra) | no (JS) | YES |
| AI agent 友好 | YES | partial | partial | no | partial | no |
| 多语言代码生成 | 4 (py/rust/go/ts) | 50+ | 10+ | no | partial | partial |
| 真实编译验证 | YES (cargo) | no | YES | no | YES | no |
| 并行 wave DAG | YES | no | no | partial | YES | no |
| Git worktree 集成 | YES | no | no | no | no | no |
| 内置可视化 | YES | YES | no | YES | no | no |
| 反模式 lint | YES (8 rules) | partial | partial | YES | YES | no |
| 自动修复 | YES | no | no | YES | partial | no |
| 远程模板 | YES | YES | YES | YES | YES | YES |
| 增量构建 | YES | no | no | YES | YES | no |
| 模板继承 / schema imports | YES | YES | YES | YES | partial | YES |

**我们的独家组合**：AI agent 友好 + blocker DAG + git worktree + 自动 fix + 客户端可视化，**五个一起做**。其他工具都没覆盖到这个完整 surface。

---

## 贡献 / Contributing

1. Fork → 改 `generators/*.sh` → 跑 `tests/test_animations.sh` → 提 PR
2. 加新 spec？编辑 `specs/*.json`，用 `jq empty` 校验
3. 加新 generator？参考 `generators/python.sh` 的 `set -euo pipefail + source _lib.sh` 模板
4. 加新动画？编辑 `generators/_lib.sh` 末尾

---

## 许可 / License

Apache License 2.0

Copyright 2026 simple_model contributors

---

## 致谢 / Acknowledgments

- 灵感来自 **Maven**（项目生命周期）、**OpenAPI**（schema → code）、**buf**（protobuf lint）、**Terraform**（drift detection）
- 设计哲学："AI agent 该用得最舒服，schema 该是真相源，工具该零依赖"
- Built with bash + jq, by AI for AI and humans.

---

**Made for AI agents that don't like waiting, and humans that like pretty terminals.**