# Codex Plugin

The plugin source of truth lives in `plugins/simple-model-project-intelligence/`.
The editable skill source lives in `codex/skills/simple-model-project-intelligence/`.
Before packaging, keep them synchronized:

```bash
tools/sync_codex_plugin.sh --check
tools/sync_codex_plugin.sh --sync
```

## Install From A Clone

```bash
git clone https://github.com/silverenternal/simple_model.git
cd simple_model
codex plugin marketplace add "$PWD"
codex plugin add simple-model-project-intelligence@simple-model
```

Start a new Codex thread after install or update, then invoke:

```text
Use $simple-model-project-intelligence to audit this repo.
```

## Diagnose

```bash
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh doctor
plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh doctor --json
```

For a separate target repository:

```bash
SIMPLE_MODEL_HOME=/path/to/simple_model \
  /path/to/simple_model/plugins/simple-model-project-intelligence/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh \
  --target-root /path/to/target-repo doctor
```

## Package

Plugin version follows the plugin manifest version. Release assets use:

```text
simple-model-project-intelligence-plugin-<plugin-version>.zip
```

Build a package:

```bash
tools/package_codex_plugin.sh --version 0.6.0
```

The script validates skill sync, marketplace JSON, plugin manifest version, command
metadata, and wrapper execution before writing `dist/`.

## Update Or Remove

For updates, pull the latest repository, rerun `codex plugin add
simple-model-project-intelligence@simple-model`, and start a new Codex thread.

For removal, use your Codex CLI's plugin removal command if available. If the CLI
does not expose one, remove or stop using the repo-local marketplace registration.

## Troubleshooting

- `cannot locate simple_model root`: set `SIMPLE_MODEL_HOME=/path/to/simple_model`.
- `jq` missing: install `jq` and rerun `doctor`.
- Old bash on macOS: run scripts with Homebrew bash 4+.
- Plugin changes not visible: reinstall the plugin and start a new Codex thread.
