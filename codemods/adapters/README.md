# Codemod Adapters

These adapters define the production contract for language-native rewrites.
The shell dispatcher keeps execution deterministic and local-only. Optional
language tools can implement the same JSON contract without changing macro
policy:

- inputs: root, operation, path, params
- outputs: edits, diagnostics, formatter, idempotency_key, rollback_hashes
- failure mode: review-only diagnostics, never partial writes

