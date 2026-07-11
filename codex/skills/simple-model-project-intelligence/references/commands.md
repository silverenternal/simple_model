# Command Reference

Use these commands from the `simple_model` repository root unless a wrapper command is shown.

## Model Lifecycle

- Diagnose plugin/toolchain readiness:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh doctor --json`
- List wrapper command metadata:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh commands --json`
- Run the plugin lifecycle gate:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh self-check --json`
- Run release validation without publishing:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh self-release --version 0.6.0 --dry-run --json`
- List deterministic optimizer macros:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macros --json`
- Generate declarative macro specs from target repo facts:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <repo-root>/struct.json macro-suggest --json`
- Compile generated specs into an executable plan:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-compile --suggestions generated/optimization/macro-suggestions.json --json`
- Score architecture health:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <repo-root>/struct.json score --json`
- Plan and dry-run macro optimization for a target repo:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <repo-root>/struct.json optimize --dry-run`
- Run the score-driven generate/compile/execute loop:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <repo-root>/struct.json optimize-loop --budget 3 --dry-run`
- Execute a saved optimization plan:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-run --plan generated/optimization/plan.json --dry-run --json`
- Validate source model:
  `./bootstrap.sh --validate`
- Resolve multi-file model:
  `./bootstrap.sh --resolve --json`
- Regenerate safe no-argument outputs:
  `./bootstrap.sh --target all`
- Check generated implementation drift:
  `./bootstrap.sh --check-all`
- Lint and drift summaries:
  `./bootstrap.sh --lint --json | jq '.summary'`
  `./bootstrap.sh --drift --json | jq '.summary'`

## Large Repo Adoption

- Draft a model from an existing repo:
  `./bootstrap.sh --ingest-repo <repo-root> --json`
- Audit unmanaged source files:
  `./bootstrap.sh --adoption-audit <repo-root> --json`
- Scan public interfaces:
  `./bootstrap.sh --interface-scan <repo-root> --json`
- Scan dynamic runtime surfaces:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <repo-root>/struct.json dynamic-surface --json`
- Plan or execute allowlisted runtime probes:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> runtime-probe --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> runtime-probe --execute --json`
- Merge runtime observations into dynamic surfaces:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh dynamic-merge --surfaces generated/intelligence/dynamic-surfaces.json --observations generated/intelligence/runtime-observations.json --json`
- Suggest struct patch operations from findings:
  `generators/struct_suggest.sh --findings <findings.json> --json`

## Macro Optimization

- Validate the macro registry:
  `generators/macro_registry.sh --json`
- Build a deterministic optimization plan from repo facts:
  `generators/optimization_plan.sh --root <repo-root> --struct <struct.json> --json`
- Generate declarative macro specs:
  `generators/macro_suggest.sh --root <repo-root> --struct <struct.json> --json`
- Compile generated macro specs:
  `generators/macro_compile.sh --suggestions generated/optimization/macro-suggestions.json --json`
- Compute architecture health score:
  `generators/optimization_score.sh --root <repo-root> --struct <struct.json> --json`
- Execute the plan without changing files:
  `generators/macro_exec.sh --plan generated/optimization/plan.json --dry-run --json`
- Apply low-risk automatic macros with rollback metadata:
  `generators/macro_exec.sh --plan generated/optimization/plan.json --apply --json`
- Run a score-gated optimization loop:
  `generators/optimization_loop.sh --root <repo-root> --struct <struct.json> --budget 3 --dry-run --json`
- Build the v0.9 Optimization Graph and rank structural candidates:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <struct.json> optimization-graph --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh optimizer-search --budget 5 --json`
- Run optimizer autopilot with bounded graph search, macro simulation, cache-aware tests, and concurrency:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <struct.json> autopilot --jobs 4 --budget 5 --mode fast --json`

## Accelerated Validation And Concurrency

- Build the test impact DAG:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh test-plan --json`
- Run accelerated checks:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh fast-check --jobs 4 --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh affected-check --changed-files generators/autopilot.sh --jobs 4 --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh full-check --jobs 4`
- Inspect the content-addressed test cache:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh test-cache --command 'bash tests/test_v04_roadmap.sh' --lookup --json`
- Plan deterministic concurrent tasks:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh scheduler-plan --tasks generated/tasks.json --jobs 4 --json`
- Generate performance SLO artifacts:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh performance-benchmark --jobs 4 --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh performance-dashboard --json`

## v1.0 Production Optimizer

- Deep structural parsing and semantic graph:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh tree-sitter-scan --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh lsp-symbols --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh semantic-graph --json`
- Simulate a production codemod:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh codemod --spec generated/codemods/spec.json --simulate --json`
- Calibrate scoring and render optimizer evidence:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh score-calibrate --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh optimizer-report --json`
- Generate framework resolvers and runtime contracts:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh framework-resolvers --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh runtime-contracts --json`
- Run production readiness:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh production-benchmark --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh adopt --json`

## v1.1 Semantic Macro Benchmark Moat

- Build confidence-aware semantic evidence:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh parser-tiers --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh symbol-index --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh semantic-graph-incremental --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh dynamic-edges --json`
- Verify macro safety before any apply path:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-preconditions --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-drill --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-generate --json`
- Prove quality and adoption readiness:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh accuracy-scorecard --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh external-eval --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh confidence-plan --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh adoption-cockpit --json`

## v1.2 Macro Maximalist Optimizer

- Discover and type macros as project optimization operators:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-operator-ir --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-motifs --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-templates --json`

## v2.0 Capability Truth

- Audit command and macro capability truth with reproducible evidence and deltas:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <repo-root>/struct.json capability-truth --fixtures <fixture-root[,fixture-root2...]> --json`
- Compose, search, and prove macro plans:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-compose --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-plan-search --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-transaction --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-proof-bundle --json`
- Learn from outcomes and gate promotion:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-ledger --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-family-ranker --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-promotion --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-gauntlet --json`
- Use product-facing macro workflows:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-cockpit --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-advisor --json`
- Take over a half-built repository and commit its public-interface policy:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <struct.json> takeover-init --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh --target-root <repo-root> --struct <struct.json> interface-stability --json`
- Render the versioned competitive pain-point study and macro-wisdom responses:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh ai-tool-research --json`

## Code Facts And Gates

- Emit strict code facts with cache:
  `generators/code_facts.sh --root <repo-root> --struct <struct.json> --json`
- Compare interface scan reports:
  `generators/interface_diff.sh --before <before.json> --after <after.json> --json`
- Gate interface drift:
  `generators/interface_drift_gate.sh --root <repo-root> --struct <struct.json> --json`
- Gate dependency drift:
  `generators/dependency_drift_gate.sh --root <repo-root> --struct <struct.json> --json`
- Apply waiver checks:
  `generators/waiver_check.sh --waivers specs/waiver.json --json`

## PR And Release

- Replay the long-horizon evolution benchmark and inspect v2 performance economics:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh evolution-benchmark --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh performance-v2 --json`
- Verify signed macro-pack provenance offline:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh macro-pack-verify --input <pack.json> --json`
- Inspect the model-portable MCP/adapter surface and run the final release gate:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh interoperability --json`
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh release-slo-v2 --json`

- Compute PR impact:
  `./bootstrap.sh --pr-impact <repo-root> --json`
- Run PR gate:
  `./bootstrap.sh --pr-gate <repo-root> --json`
- Run PR gate and write Markdown:
  `generators/pr_gate.sh --root <repo-root> --struct <struct.json> --markdown generated/pr-comment.md --json`
- Produce a release contract from interface diff:
  `generators/release_contract.sh --diff <interface-diff.json> --json`
- Generate static dashboard:
  `generators/dashboard.sh generated/dashboard.html`
- Run the local dynamic governance case study:
  `codex/skills/simple-model-project-intelligence/scripts/simple_model_pi.sh dynamic-case-study --json`

## Multi-Repo And Agent Evaluation

- Resolve federation:
  `generators/federation_resolve.sh --json`
- Plan deterministic batches:
  `generators/batch_plan.sh --json`
- Run evolution harness:
  `examples/evolution-bench/run.sh`
- Run agent eval smoke:
  `bash tests/test_agent_eval_harness.sh`
