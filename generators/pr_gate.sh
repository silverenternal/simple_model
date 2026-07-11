#!/usr/bin/env bash
set -euo pipefail
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."; STRUCT="${STRUCT_FILE:-./struct.json}"; FILES=""; JSON_OUT=0; MARKDOWN_OUT=""
while [[ $# -gt 0 ]]; do case "$1" in --root) ROOT="$2"; shift 2;; --struct|-s) STRUCT="$2"; shift 2;; --files) FILES="$2"; shift 2;; --json) JSON_OUT=1; shift;; --markdown) MARKDOWN_OUT="$2"; shift 2;; *) shift;; esac; done
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
impact_file="$tmp/impact.json"; iface_file="$tmp/interface.json"; dep_file="$tmp/dependency.json"; risk_file="$tmp/risk.json"; tests_file="$tmp/tests.json"; review_file="$tmp/review.json"; dynamic_file="$tmp/dynamic.json"; ok_file="$tmp/ok.json"
bash "$SELF_DIR/pr_impact.sh" --root "$ROOT" --struct "$STRUCT" --files "$FILES" --json > "$impact_file"
bash "$SELF_DIR/interface_drift_gate.sh" --root "$ROOT" --struct "$STRUCT" --json > "$iface_file" || true
bash "$SELF_DIR/dependency_drift_gate.sh" --root "$ROOT" --struct "$STRUCT" --json > "$dep_file" || true
bash "$SELF_DIR/risk_score.sh" --json < "$impact_file" > "$risk_file"
bash "$SELF_DIR/test_select.sh" --json < "$impact_file" > "$tests_file"
bash "$SELF_DIR/review_route.sh" --json < "$impact_file" > "$review_file"
bash "$SELF_DIR/dynamic_surface_scan.sh" --root "$ROOT" --struct "$STRUCT" --json > "$dynamic_file" || jq -n '{nodes:[],summary:{nodes:0}}' > "$dynamic_file"
jq -n --slurpfile i "$iface_file" --slurpfile d "$dep_file" '(($i[0] // {ok:false}).ok and ($d[0] // {ok:false}).ok)' > "$ok_file"
out=$(jq -n --slurpfile ok_file "$ok_file" --slurpfile impact_file "$impact_file" --slurpfile iface_file "$iface_file" --slurpfile dep_file "$dep_file" --slurpfile risk_file "$risk_file" --slurpfile tests_file "$tests_file" --slurpfile review_file "$review_file" --slurpfile dynamic_file "$dynamic_file" --arg files "$FILES" '
  ($ok_file[0] // false) as $ok
  | ($impact_file[0] // {}) as $impact
  | ($iface_file[0] // {}) as $interface
  | ($dep_file[0] // {}) as $dependency
  | ($risk_file[0] // {}) as $risk
  | ($tests_file[0] // {}) as $tests
  | ($review_file[0] // {}) as $review
  | ($dynamic_file[0] // {nodes:[],summary:{nodes:0}}) as $dynamic
  | {
  ok:$ok,
  impact:$impact,
  gates:{interface:$interface, dependency:$dependency},
  risk:$risk.risk,
  tests:$tests.commands,
  review:$review,
  dynamic:{
    summary:$dynamic.summary,
    affected:(
      ($dynamic.nodes // [])
      | map(. as $node | select(
          ($files == "")
          or (($files | split(",") | map(gsub("^\\s+|\\s+$"; ""))) as $fs | $fs | any(. == $node.path or ($node.path|endswith(.)) or (.|endswith($node.path))))
        ))
    ),
    dynamic_unverified:(($dynamic.nodes // []) | map(select(.risk_level=="dynamic_unverified"))),
    dynamic_unsafe:(($dynamic.nodes // []) | map(select(.risk_level=="dynamic_unsafe"))),
    probe_recommendations:($dynamic.probe_recommendations // [])
  }
}')
if [[ -n "$MARKDOWN_OUT" ]]; then
    mkdir -p "$(dirname "$MARKDOWN_OUT")"
    echo "$out" | bash "$SELF_DIR/pr_comment.sh" > "$MARKDOWN_OUT"
fi
[[ "$JSON_OUT" == "1" ]] && echo "$out" || jq -r '.'
jq -e '. == true' "$ok_file" >/dev/null || exit 1
