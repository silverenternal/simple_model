#!/usr/bin/env bash
set -euo pipefail
MACRO=""; FIXTURES=""; OUT="generated/macros/macro-certificate.json"; JSON_OUT=0; SIGNING_KEY="${SIMPLE_MODEL_CERT_KEY:-simple-model-local-certification-key-v1}"
while [[ $# -gt 0 ]]; do
  case "$1" in --macro) MACRO="$2"; shift 2 ;; --fixtures) FIXTURES="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --signing-key) SIGNING_KEY="$2"; shift 2 ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$MACRO" && -d "$FIXTURES" ]] || { echo "--macro and --fixtures required" >&2; exit 64; }
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
macro_hash="$(jq -S -c . "$MACRO" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
fixture_hash="$(find "$FIXTURES" -maxdepth 1 -type f -name '*.json' -print | sort | while read -r f; do printf '%s\n' "$(basename "$f")"; jq -S -c . "$f"; done | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
content_hash="$(printf '%s:%s' "$macro_hash" "$fixture_hash" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
required=(positive negative adversarial partial_parse dirty_worktree rollback)
missing=(); for kind in "${required[@]}"; do [[ -f "$FIXTURES/$kind.json" ]] || missing+=("$kind"); done
obligations="$tmp/obligations.jsonl"; : > "$obligations"
for kind in "${required[@]}"; do
  if [[ ! -f "$FIXTURES/$kind.json" ]]; then printf '%s\n' "$(jq -n --arg kind "$kind" '{name:("fixture:"+$kind),passed:false,reason:"missing mandatory fixture"}')" >> "$obligations"; continue; fi
  jq -c --arg kind "$kind" '. as $f | [
    {name:("fixture:"+$kind),passed:true,reason:"mandatory fixture present"},
    {name:"match_precision",passed:($f.proofs.match_precision==true),reason:(if $f.proofs.match_precision==true then "labeled match proof present" else "add labeled true/false matches and rerun" end)},
    {name:"bounded_effects",passed:($f.proofs.bounded_effects==true and (($f.expected.write_paths|type)=="array")),reason:(if ($f.proofs.bounded_effects==true and (($f.expected.write_paths|type)=="array")) then "write set is bounded" else "declare a bounded write_paths set" end)},
    {name:"idempotency",passed:($f.proofs.idempotency==true),reason:(if $f.proofs.idempotency==true then "replay output is stable" else "run the macro twice and compare artifact hashes" end)},
    {name:"rollback",passed:($f.proofs.rollback==true),reason:(if $f.proofs.rollback==true then "rollback proof present" else "add an interrupted/failing run and verify restore" end)},
    {name:"composition",passed:($f.proofs.composition==true),reason:(if $f.proofs.composition==true then "composition proof present" else "supply a conflict and a compatible composition fixture" end)},
    {name:"test_impact",passed:($f.proofs.test_impact==true and (($f.observations.affected_tests|type)=="array") and (($f.observations.affected_tests|length)>0)),reason:(if ($f.proofs.test_impact==true and (($f.observations.affected_tests|type)=="array") and (($f.observations.affected_tests|length)>0)) then "affected tests recorded" else "record affected tests for the fixture" end)},
    {name:"performance",passed:($f.proofs.performance==true and (($f.observations.duration_ms//999999)<=1000)),reason:(if ($f.proofs.performance==true and (($f.observations.duration_ms//999999)<=1000)) then "bounded fixture duration" else "add a performance observation within the limit" end)},
    {name:"external_generality",passed:($f.proofs.external_generality==true and (($f.observations.external_repo//false)==true)),reason:(if ($f.proofs.external_generality==true and (($f.observations.external_repo//false)==true)) then "external repository fixture observed" else "run the macro against an external repository fixture" end)}
  ][]' "$FIXTURES/$kind.json" >> "$obligations"
done
proofs="$(jq -s '.' "$obligations")"; failed="$(jq '[.[]|select(.passed|not)]' <<<"$proofs")"; certified="$(jq 'length==0' <<<"$failed")"
remediation="$(jq '[.[]|select(.passed|not)|{obligation:.name,action:.reason}]' <<<"$proofs")"
required_json="$(printf '%s\n' "${required[@]}" | jq -R . | jq -s .)"
payload="$(jq -n --arg macro_id "$(jq -r '.id // .macro_id // "unknown"' "$MACRO")" --arg macro_hash "$macro_hash" --arg fixture_hash "$fixture_hash" --arg content_hash "$content_hash" --argjson certified "$certified" --argjson proofs "$proofs" --argjson remediation "$remediation" --argjson required "$required_json" '{schema_version:"1.0",macro_id:$macro_id,certified:$certified,trusted:$certified,apply_mode_allowed:$certified,proof_obligations:$proofs,remediation:$remediation,inputs:{macro_hash:$macro_hash,fixture_hash:$fixture_hash,content_hash:$content_hash},required_fixture_kinds:$required,policy:{uncertified_trusted_macros:0,review_only_until_certified:true}}')"
certificate_hash="$(jq -S -c . <<<"$payload" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
signature="$(printf '%s:%s' "$certificate_hash" "$SIGNING_KEY" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
report="$(jq --arg hash "$certificate_hash" --arg signature "$signature" '$ARGS.named as $n | . + {certificate_hash:$n.hash,signature:{algorithm:"sha256-local",signer:"simple-model-local",value:$n.signature}}' --arg hash "$certificate_hash" --arg signature "$signature" <<<"$payload")"
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Macro certificate \(.macro_id) certified=\(.certified) trusted=\(.trusted)"' "$OUT"; fi
jq -e '.certified==true' "$OUT" >/dev/null
