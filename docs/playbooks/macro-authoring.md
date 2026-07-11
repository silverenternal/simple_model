# Macro Authoring Playbook

Use this when adding a new deterministic optimization macro.

```bash
simple_model_pi.sh macro-family-suggest --json
simple_model_pi.sh macro-suggest --json
simple_model_pi.sh macro-compile --json
simple_model_pi.sh macro-simulate --plan generated/optimization/plan.json --json
```

Every macro must declare Macro IR v2 safety fields, fixture coverage,
simulation behavior, rollback behavior, and policy interaction.
