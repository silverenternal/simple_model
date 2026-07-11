# Adapter SDK v1 fixtures

Each executable in `adapters/` implements two calls:

```text
adapter.sh --manifest
adapter.sh --request <request.json>
```

The manifest negotiates the protocol version, capability, language, provenance,
timeout, output limit, and sandbox. A request carries a stable id and a current
SHA-256 input. A response is accepted only when the harness can replay it byte
for byte, match the request identity and hash, and prove that rewrite paths stay
inside the declared sandbox.

The five reference adapters are parser-only, query-only, rewrite, runtime
evidence, and an unavailable optional parser backend. The last one demonstrates
the fail-closed behavior: it returns `review_only` and can never promote a
structural decision when the optional backend is missing.
