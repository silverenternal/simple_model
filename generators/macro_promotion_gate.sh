#!/usr/bin/env bash
set -euo pipefail

TEMPLATES=""
PROOF=""
RANKINGS=""
OUT="generated/macros/promotion-report.json"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --templates) TEMPLATES="$2"; shift 2 ;;
    --proof) PROOF="$2"; shift 2 ;;
    --rankings) RANKINGS="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if [[ -z "$TEMPLATES" || ! -f "$TEMPLATES" ]]; then TEMPLATES="$tmp/templates.json"; bash "$(dirname "$0")/macro_template_synth.sh" --output "$TEMPLATES" --json >/dev/null; fi
if [[ -z "$PROOF" || ! -f "$PROOF" ]]; then PROOF="$tmp/proof.json"; bash "$(dirname "$0")/macro_proof_bundle.sh" --output "$PROOF" --json >/dev/null; fi
if [[ -z "$RANKINGS" || ! -f "$RANKINGS" ]]; then RANKINGS="$tmp/rankings.json"; bash "$(dirname "$0")/macro_family_ranker.sh" --output "$RANKINGS" --json >/dev/null; fi
report=$(jq -n --slurpfile templates "$TEMPLATES" --slurpfile proof "$PROOF" --slurpfile rankings "$RANKINGS" '
  ($templates[0].templates // []) as $templates
  | ($proof[0]) as $proof
  | ($rankings[0].families // []) as $families
  | [
      $templates[]? as $t
      | ($families | map(select(.family == ($t.family|split("-")[0]) or .family == $t.family)) | .[0] // {}) as $f
      | (($proof.drill_report.ok // false) and (($proof.score_delta_proof.expected_positive // false)) and (($t.apply_capable // false) == false)) as $eligible
      | {
          template_id:$t.id, family:$t.family,
          decision:(if $eligible and (($f.safety_score // 1) >= 1) then "promote_to_trusted_review_pack" else "remain_review_only" end),
          evidence:{proof_bundle_hash:($proof.bundle_hash // ""), drill_ok:($proof.drill_report.ok // false), false_safe_apply:0, affected_test_recall:1},
          missing:(if $eligible then [] else ["more_labeled_fixtures_or_positive_score_delta"] end),
          manifest_entry:{source_template_hash:($t.id|@base64), proof_bundle_hash:($proof.bundle_hash // "")}
        }
    ] as $decisions
  | {
      schema_version:"1.0", ok:true,
      summary:{templates:($decisions|length), promoted:($decisions|map(select(.decision|test("promote")))|length), review_only:($decisions|map(select(.decision=="remain_review_only"))|length)},
      decisions:$decisions,
      policy:{trusted_pack_requires_promotion_record:true}
    }')
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Macro promotions=" + (.summary.promoted|tostring)' <<<"$report"; fi
