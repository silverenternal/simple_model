#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
GRAPH=""
DYNAMIC=""
TIERS=""
OUT="generated/macros/motif-candidates.json"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --graph) GRAPH="$2"; shift 2 ;;
    --dynamic-edges) DYNAMIC="$2"; shift 2 ;;
    --parser-tiers) TIERS="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"
STRUCT="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"
mkdir -p "$(dirname "$OUT")"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if [[ -z "$GRAPH" ]]; then
  GRAPH="$tmp/graph.json"
  if [[ -f generated/intelligence/semantic-graph.json ]]; then cp generated/intelligence/semantic-graph.json "$GRAPH"; else bash "$SELF_DIR/semantic_graph_incremental.sh" --root "$ROOT" --struct "$STRUCT" --output "$GRAPH" --diff-output "$tmp/diff.json" --json >/dev/null; fi
fi
if [[ -z "$DYNAMIC" ]]; then
  DYNAMIC="$tmp/dynamic.json"
  if [[ -f generated/intelligence/dynamic-edges.json ]]; then cp generated/intelligence/dynamic-edges.json "$DYNAMIC"; else bash "$SELF_DIR/dynamic_edge_resolver.sh" --root "$ROOT" --struct "$STRUCT" --output "$DYNAMIC" --json >/dev/null; fi
fi
if [[ -z "$TIERS" ]]; then
  TIERS="$tmp/tiers.json"
  if [[ -f generated/intelligence/parser-tiers.json ]]; then cp generated/intelligence/parser-tiers.json "$TIERS"; else bash "$SELF_DIR/parser_tier_registry.sh" --root "$ROOT" --output "$TIERS" --json >/dev/null; fi
fi

report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --slurpfile graph "$GRAPH" --slurpfile dyn "$DYNAMIC" --slurpfile tiers "$TIERS" '
  def cid($s): ($s|gsub("[^A-Za-z0-9_.:-]"; "_"));
  ($graph[0].nodes // []) as $nodes
  | ($graph[0].edges // []) as $edges
  | ($dyn[0].edges // []) as $dyn_edges
  | ($tiers[0].files // []) as $tier_files
  | (
      [
        $edges[]? | select(.kind=="symbol_exports_interface")
        | {motif:"boundary_drift", family:"boundary-repair", graph_path:[.from,.to], confidence:(.confidence // 0.7), review_reason:"verify public boundary before export repair", missing_proof:["operator_ir","composition","drill"]}
      ]
      + [
        $dyn_edges[]? | select(.blocks_safe_apply == true)
        | {motif:"dynamic_evidence_gap", family:"framework-repair", graph_path:[.from,.to], confidence:(.confidence // 0.5), review_reason:"dynamic edge blocks safe apply", missing_proof:["runtime_observation","trusted_dynamic_evidence"]}
      ]
      + [
        $tier_files[]? | select((.confidence // 1) < 0.8)
        | {motif:"parser_confidence_gap", family:"evidence-gathering", graph_path:[.path], confidence:(.confidence // 0.5), review_reason:"parser confidence below safe automation floor", missing_proof:["better_parser_or_lsp"]}
      ]
      + [
        $nodes[]? | select((.kind // "")|test("generated|dynamic"))
        | {motif:"generated_or_dynamic_surface", family:"surface-governance", graph_path:[.id], confidence:(.confidence // 0.6), review_reason:"generated/dynamic surface needs provenance proof", missing_proof:["source_contract","runtime_contract"]}
      ]
    ) as $raw
  | ($raw | map(. + {
      id:("motif:" + cid(.motif + ":" + (.graph_path|join(":")))),
      apply_capable:false,
      action:(if .confidence < 0.8 then "gather-evidence" else "review-first" end),
      evidence:{source:"macro_discover_motifs", clustered_by:"semantic_graph_motif"}
    }) | unique_by(.id) | sort_by(.motif,.id)) as $candidates
  | {
      schema_version:"1.0", ok:true, root:$root, struct:$struct,
      summary:{candidates:($candidates|length), gather_evidence:($candidates|map(select(.action=="gather-evidence"))|length), review_first:($candidates|map(select(.action=="review-first"))|length), apply_capable:0},
      candidates:$candidates,
      policy:{cluster_by_graph_motif:true, low_confidence_never_apply:true}
    }')
printf '%s\n' "$report" > "$OUT"
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Macro motifs=" + (.summary.candidates|tostring)' <<<"$report"; fi
