# Messy Monorepo Adoption Playbook

Use this when a repository contains multiple apps, packages, services, or
workspace roots.

```bash
simple_model_pi.sh --target-root /path/to/repo workspace-graph --json
simple_model_pi.sh --target-root /path/to/repo index-cache --json
simple_model_pi.sh --target-root /path/to/repo context-pack --workflow adopt --json
simple_model_pi.sh --target-root /path/to/repo autopilot --dry-run --json
simple_model_pi.sh --target-root /path/to/repo dynamic-surface --json
simple_model_pi.sh --target-root /path/to/repo runtime-probe --json
```

Do not apply boundary-repair macros until workspace ownership, release units,
and policy constraints have been reviewed.

For dynamic-heavy projects, treat unobserved dynamic imports, plugin registries,
DI bindings, env-gated loaders, generated clients, and monkey patches as
governance inputs. They need runtime probes or explicit expiring waivers before
automated macros can apply changes.
