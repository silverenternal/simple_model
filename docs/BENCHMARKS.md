# Benchmarks

The semantic plugin benchmark scorecard runs the local fixture corpus under
`benchmarks/semantic-plugin-corpus`. The corpus includes a manifest-driven
20+ case suite spanning Python, TypeScript, JavaScript, Go, Rust, contract
files, config surfaces, and unsupported-language negative controls. It measures:

- parser precision and recall
- adoption quality
- macro simulation safety
- runtime budget readiness
- release SLO eligibility
- dynamic precision and recall
- dynamic observation coverage
- dynamic unsafe detection rate

Each fixture has a real repository shape, `struct.json`, and `expected.json`.
The scorecard runs semantic IR extraction and computes precision/recall from
actual detected symbols, routes, and contracts.

v0.8 adds dynamic-code fixtures for decorators, router registration, DI
containers, plugin manifests, event buses, generated code, env-gated loading,
monkey patching, dynamic imports, worker registration, and Go reflection.
Dynamic metrics are local project capability checks, not external
certification.

Run locally:

```bash
bash generators/benchmark_scorecard.sh . --json
bash generators/competitive_scorecard.sh --json
bash generators/release_slo.sh --json
```

The scorecard is local-first and telemetry-free.
