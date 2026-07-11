# Release SLO

Plugin releases must satisfy:

- full validation and plugin self-check
- deterministic package manifest and checksums
- semantic benchmark scorecard thresholds computed from the local corpus
- parser precision and recall minimums
- macro simulation safety at 100%
- dynamic precision and recall minimums
- dynamic observation coverage minimums
- dynamic unsafe detection rate minimums
- documented command and macro changes

`generators/release_slo.sh` evaluates benchmark gates before publish. A release
exception must be represented as an explicit local waiver, never as a silent
skip.

Dynamic waivers must be explicit, expiring, and attached to policy evidence for
automated macro apply. Unobserved or unsafe dynamic surfaces are review-only by
default.
# Release SLO

Release SLO combines parser quality, dynamic governance, macro safety, and
performance budgets. The gate is deterministic and reads generated JSON only.

## Commands

```bash
generators/performance_benchmark.sh --root . --struct ./struct.json --jobs 4 --json
generators/performance_dashboard.sh --json
generators/release_slo.sh --version 0.6.0 --json
```

## Performance Budgets

- `fast_check_seconds`: maximum warm fast-check runtime.
- `full_check_seconds`: maximum release full-check runtime target.
- `min_cache_hit_rate`: expected lower bound for repeated validation.
- `min_parallel_speedup`: required serial-vs-parallel improvement floor.
- `deterministic_hash`: stable hash over benchmark outputs used to detect
  scheduler nondeterminism.

When a budget fails, inspect `generated/performance/scorecard.json`,
`generated/tests/test-runner.json`, and `generated/performance/dashboard.html`.
