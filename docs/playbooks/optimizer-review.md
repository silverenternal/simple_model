# Optimizer Review

Use optimizer reports as review inputs, not as blind apply instructions.

1. Build `optimization_graph.sh`.
2. Run `optimizer_search.sh`.
3. Render `optimizer_report.sh`.
4. Simulate selected macros.
5. Run affected checks.
6. Apply only if policy, rollback, dynamic evidence, and tests pass.
