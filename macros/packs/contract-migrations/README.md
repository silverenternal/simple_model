# Contract migration macro pack

The compiler turns OpenAPI, AsyncAPI, protobuf, GraphQL, SQL, dependency, and
configuration diffs into staged review plans. Compatible additions land first,
then shims/deprecations, consumer updates, data backup/validation, and explicit
breaking approval. Rollback order is always the reverse stage order.
