# Macro Query Language (MQL)

MQL is a closed, deterministic JSON query language over Unified Program Graph v3. A query contains a typed `match`, a unique `capture`, an optional array of negative patterns, an optional bounded traversal, and a quantifier (`any`, `all`, or `count`). Regex fields use jq regular expressions.

```json
{"schema_version":"1.0","match":{"kind":"^interface\\.","evidence_class":"parsed","confidence_gte":0.7},"capture":"public_interface","traverse":{"direction":"out","edge_kind":"contract","min_depth":1,"max_depth":3,"to":{"kind":"contract"},"capture":"contract"},"quantifier":"count"}
```

`mql_plan.sh` rejects duplicate captures and traversal depth outside 1–8. Plans contain normalized queries, explicit operators, cost estimates, an explanation trace, and a deterministic hash. `mql_execute.sh` never evaluates arbitrary jq supplied by a query.
