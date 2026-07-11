# Dynamic Code Governance

Dynamic governance makes runtime behavior explicit before an agent or macro
changes code. The workflow is deterministic:

1. Run `dynamic-surface` to extract routes, DI bindings, plugin registrations,
   event subscriptions, dynamic imports, generated interfaces, env gates,
   reflection, monkey patches, and unsafe execution.
2. Run `runtime-probe --dry-run` to inspect the local probe allowlist.
3. Run `runtime-probe --execute` only when the repository has an explicit
   `.simple_model/probes.json` policy.
4. Merge observations with `dynamic-merge` and use the merged graph for
   adoption reports, PR gates, policy evaluation, and macro simulation.
5. Treat `dynamic_unsafe` and unobserved dynamic surfaces as review-only unless
   an explicit expiring waiver exists.

The case study in `examples/dynamic-case-study` is local-only and reproducible.
