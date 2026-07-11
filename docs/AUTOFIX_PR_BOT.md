# Autofix PR Bot

`generators/autofix_pr_plan.sh` creates a dry-run PR plan for low-risk,
policy-allowed macro improvements. It does not create branches or PRs by
default.

Required production sequence:

```bash
bash generators/optimization_plan.sh --json
bash generators/macro_simulate.sh --plan generated/optimization/plan.json --json
bash generators/policy_eval.sh --plan generated/optimization/plan.json --json
bash generators/autofix_pr_plan.sh --plan generated/optimization/plan.json --json
```

Only low/medium risk, auto-apply macros may be converted to an autofix branch.
High-risk candidates are emitted as review-only tasks.
