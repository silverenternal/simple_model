# v2 production release SLO

The release_slo_v2 generator is the deterministic final gate for the
executable macro program. It requires external and held-out corpus evidence,
the 500-case gauntlet, resumable long-horizon evidence, cache-disabled
performance data, hermetic replay, offline macro-pack verification, and the
four reference ecosystem adapters. The report is content-addressed and
includes five signed plugin summaries: maturity, benchmark, proof,
performance, and compatibility.

The gate fails closed if any program target is missing, if false-safe-apply is
nonzero, or if a required evidence artifact is absent. All JSON decisions are
portable across CLI, MCP, plugin, and CI clients.
