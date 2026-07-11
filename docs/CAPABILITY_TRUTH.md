# Capability Truth Audit

`generators/capability_truth_audit.sh` computes a reproducible capability statement for the
current repository and command pipeline.

## What it audits

- **Analyze** capability: parser tier extraction + symbol identity + semantic graph synthesis.
- **Simulate** capability: optimization plan generation + macro simulation run.
- **Apply** capability: macro execution with rollback artifacts.
- **Rollback/Replay** capability: deterministic transactional execution and repeatable replays.
- **Generalization** capability: fixture portability across selected repositories.

## Inputs

- `--root PATH` target repository (defaults to current directory).
- `--struct PATH` struct model (defaults to `struct.json`).
- `--spec PATH` gates and thresholds JSON.
- `--output PATH` output artifact path.
- `--fixtures LIST` comma-separated fixture roots to validate generalization.
- `--json` print JSON report directly.

## Output

Report format: `generated/audits/capability-truth.json`

Key fields:

- `ok`: overall truth claim (all core gates passed).
- `capabilities.{analyze,simulate,apply,rollback_replay,generalization}`: gate-by-gate verdict.
- `maturity.level`: `none`, `foundational`, `intermediate`, `core`, `advanced`.
- `maturity.score` and `maturity.max_score`: deterministic gate score.
- `artifacts`: produced machine-addressable artifact paths and hashes.
- `delta`: comparison against previous `generated/audits/capability-truth.json`.

## Interpretation

A command is considered production-safe at a gate only when
its dedicated pipeline has evidence, rollback/replay coverage, and required
fixtures succeed under the configured success ratio. Any missing evidence keeps
its capability false.

## Plugin usage

The plugin command is:

- `simple_model_pi.sh capability-truth --json`

with optional `--root`, `--struct`, `--spec`, `--output`, and `--fixtures` arguments.
