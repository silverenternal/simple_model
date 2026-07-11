# Concurrent Execution Playbook

simple_model concurrency is deterministic by default. Tasks must declare inputs,
outputs, dependencies, timeout, resource class, and cache policy before the
scheduler runs them.

## Safety Classes

- `read-only`: graph generation, scans, test planning, score reports, dashboards.
- `validation`: smart test runner and benchmark checks. These may write isolated
  generated output directories and test cache entries.
- `simulation-only`: macro simulation can run with `--jobs N`, but it only applies
  macros inside disposable sandboxes.
- `apply-only`: macro apply and release publish are intentionally outside the MCP
  allowlist and require explicit local CLI intent.

## Required Conventions

- Use `generators/parallel_scheduler.sh --tasks <file> --jobs N` for task DAGs.
- Use isolated output directories for concurrent tasks unless the task declares a
  shared lock.
- Use `_concurrency.sh` helpers for atomic writes and lock files.
- Treat duplicate output paths as a deterministic conflict unless a command has a
  documented merge strategy.
- Keep event logs append-only during a run and verify them with
  `generators/run_log.sh --replay`.

## Validation Modes

- `fast-check`: core and adoption tests for local iteration.
- `affected-check`: impacted tests selected by changed files.
- `dynamic-check`: dynamic surface and runtime governance tests.
- `plugin-check`: plugin packaging and wrapper command tests.
- `benchmark-check`: benchmark and release SLO tests.
- `full-check`: release-grade validation.
