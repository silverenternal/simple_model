# Adapter SDK v1

The adapter boundary lets parsers, query engines, native refactoring tools,
LSPs, and runtime collectors contribute facts without giving them structural
authority. The protocol is defined in `specs/adapter-protocol-v1.json` and is
intentionally executable through two calls:

```text
adapter --manifest
adapter --request request.json
```

The manifest must declare a semantic version, capabilities (`parser`, `query`,
`rewrite`, or `runtime_evidence`), languages, provenance, a positive timeout and
output limit, and a network-disabled sandbox. Requests contain a stable id,
operation, language, and a current SHA-256 input. Responses repeat those values,
carry typed results and provenance, and always set `fail_closed: true`.

`tools/adapter_harness.sh` negotiates the manifest, enforces the timeout and
output limit, rejects stale or partial responses, replays the request to detect
nondeterminism, and checks rewrite paths against the declared sandbox. An
unavailable optional backend is valid only as `status: unavailable` with
`decision: review_only` or `reject`; it cannot claim an accepted result.

Run the five reference fixtures and emit the measured protocol rate with:

```bash
bash generators/adapter_conformance.sh --json
bash tests/test_v20_adapter_sdk.sh
```
