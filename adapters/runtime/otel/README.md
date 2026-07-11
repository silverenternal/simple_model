# OTEL runtime adapter

The adapter accepts OTLP/JSON exports or the offline fixture shape consumed by
runtime_trace_ingest.sh. It emits only normalized edge metadata, hashes trace
identifiers, and records attribute keys without retaining payload values.
