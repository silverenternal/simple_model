# Fleet campaigns

A campaign begins with a deterministic read-only impact plan and sorted cohorts.
The first cohort is the canary. A canary failure pauses all later cohorts and
records rollback/remediation. SCM writes are disabled unless explicit write
intent is supplied; every repository receives a stable idempotency key.
