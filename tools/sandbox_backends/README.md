# Sandbox backend contracts

The local, container, and nix backends use the same transaction contract:
declared tools/environment, network disabled, bounded output/time, relative
write-set, content-addressed checkpoints, and fail-closed rollback. Container
and Nix are optional integrations; when their host tool is absent, the runner
reports an actionable review-only status instead of claiming a stronger sandbox.
