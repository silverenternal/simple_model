# Macro Packs

Macro packs are versioned collections of deterministic optimization macros.
Each pack declares supported languages, frameworks, parser requirements, risk,
validations, and fixture coverage in `macros/registry.json`.

Production rules:

- generated macro families compile into normal Macro IR before execution
- every macro declares an execution tier: `advisory`, `exec_readonly`,
  `struct_only`, `safe_codemod`, or `risky_codemod`
- every write declares read/write sets, invariants, preconditions,
  postconditions, risk, and rollback
- simulation must run before apply for `safe_codemod` and `risky_codemod`
- high-risk macros are advisory unless policy explicitly permits them

The initial production pack is `semantic-refactor`, covering component adoption,
boundary repair, route grouping, contract export sync, and test placement
advisory flows.
