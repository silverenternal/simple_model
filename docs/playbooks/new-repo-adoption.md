# New Repo Adoption Playbook

Use this when a target repository has no `struct.json`.

```bash
simple_model_pi.sh --target-root /path/to/repo onboard --json
simple_model_pi.sh --target-root /path/to/repo project-structure --json
simple_model_pi.sh --target-root /path/to/repo semantic-ir --json
simple_model_pi.sh --target-root /path/to/repo autopilot --dry-run --json
```

Review the generated struct draft, semantic IR, score, macro suggestions, and
context pack before applying any write-capable macro.
