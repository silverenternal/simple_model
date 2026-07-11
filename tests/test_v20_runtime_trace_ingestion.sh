#!/usr/bin/env bash
set -euo pipefail
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
jq -n '[{trace_id:"trace-1",span_id:"span-1",edge_id:"edge:api->db",from:"api",to:"db",environment:"test",build:"build-1",commit:"abc",sampling:1.0,freshness:"current",coverage:0.8,attributes:{"user.email":"secret@example.com","http.method":"GET"},payload:{token:"super-secret"}},{trace_id:"trace-2",span_id:"span-2",edge_id:"edge:api->db",from:"api",to:"db",environment:"test",build:"build-1",commit:"abc",sampling:0.5,freshness:"current",coverage:0.7,attributes:{"http.method":"GET"},payload:{password:"secret"}}]' > "$tmp/traces.json"
bash generators/runtime_trace_ingest.sh --input "$tmp/traces.json" --output "$tmp/evidence.json" --json >/dev/null
! rg -q 'super-secret|secret@example.com|password' "$tmp/evidence.json"
jq -e '.summary.sensitive_payload_retention==0 and .summary.static_uncertainty_preserved and all(.observations[]; .provenance.environment and .provenance.build and .provenance.commit and (.payload_retained==false))' "$tmp/evidence.json" >/dev/null
bash generators/runtime_evidence_compact.sh --input "$tmp/evidence.json" --output "$tmp/compact.json" --json >/dev/null
jq -e '.summary.compacted and (.observations|length)==1 and .observations[0].sample_count==2' "$tmp/compact.json" >/dev/null
jq -e '.schema_version=="2.0"' adapters/runtime/otel/fixture.json >/dev/null
echo "  [OK] runtime trace redaction/provenance/compact static uncertainty preserved"
