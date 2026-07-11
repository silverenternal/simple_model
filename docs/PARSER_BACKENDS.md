# Parser Backends

`generators/parser_backends.sh` reports the parser path used for each supported
language, target-repo file counts, backend evidence, confidence, and whether the
result is high-confidence or a deterministic fallback. Regex-only extraction is
never considered a production-grade primary parser.

Production commands should prefer:

- compiler or AST backends when available
- comment/string-aware structural fallbacks when compiler tooling is missing
- explicit confidence and unsupported-construct reporting
- semantic IR output with parser provenance, confidence, signature, and stable
  hash on every node

Run:

```bash
bash generators/parser_backends.sh --root . --json
bash generators/deep_parser_probe.sh --root . --json
bash generators/semantic_interface_ir.sh --root . --struct struct.json --json
```
