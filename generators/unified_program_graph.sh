#!/usr/bin/env bash
set -euo pipefail

SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
OUT="generated/intelligence/program-graph-v3.json"
PARTITIONS="generated/intelligence/program-graph-v3.partitions"
REPOSITORY=""
PEER_GRAPHS=()
JSON_OUT=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --output|-o) OUT="$2"; shift 2 ;;
    --partitions) PARTITIONS="$2"; shift 2 ;;
    --repository) REPOSITORY="$2"; shift 2 ;;
    --peer-graph) PEER_GRAPHS+=("$2"); shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

ROOT="$(cd "$ROOT" && pwd)"
STRUCT="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"
[[ -n "$REPOSITORY" ]] || REPOSITORY="$(jq -r '.name // empty' "$STRUCT" 2>/dev/null || true)"
[[ -n "$REPOSITORY" ]] || REPOSITORY="$(basename "$ROOT")"
mkdir -p "$(dirname "$OUT")" "$PARTITIONS"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

bash "$SELF_DIR/semantic_graph_incremental.sh" --root "$ROOT" --struct "$STRUCT" --output "$tmp/semantic.json" --diff-output "$tmp/diff.json" --cache "$tmp/cache.json" --json >/dev/null

jq --arg repo "$REPOSITORY" '
  def clean: gsub("[^A-Za-z0-9_.:-]";"_");
  def language($n):
    ($n.evidence.language // (if ($n.path|endswith(".py")) then "python" elif ($n.path|test("\\.[cm]?[jt]sx?$")) then "typescript" elif ($n.path|endswith(".go")) then "go" elif ($n.path|endswith(".rs")) then "rust" else "neutral" end));
  def logical_id($n):
    ($n.kind // "unknown") as $kind
    | ($n.name // "") as $name
    | if $name != "" then "upg:" + $repo + ":" + (language($n)|clean) + ":" + ($kind|clean) + ":" + (($n.component // "")|clean) + ":" + ($name|clean)
      else "upg:" + $repo + ":anonymous:" + (($n.id // "")|clean) end;
  def ev($x):
    ($x.evidence // {}) as $e
    | {class:(if ($e.evidence_class? != null) then $e.evidence_class elif ($e.source // "") == "dynamic_edge_resolver" then "runtime" elif ($e.source? != null) then "parsed" else "unknown" end),
       confidence:($x.confidence // 0), provenance:[($e.source // "unknown")], freshness:"current",
       invalidation_keys:([($x.hash // empty), ($e.path // empty), ($x.path // empty)] | map(select(length > 0)) | unique | sort)};
  ([.nodes[] | . as $n | {key:$n.id,value:logical_id($n)}] | from_entries) as $idmap
  | [.nodes[] | . as $n | {id:logical_id($n),kind:$n.kind,name:($n.name // ""),path:($n.path // ""),repository:$repo,component:($n.component // ""),source_id:$n.id,evidence:ev($n)}] as $nodes
  | [.edges[] | . as $e | {id:("upg-edge:"+$repo+":"+($e.kind|clean)+":"+(($idmap[$e.from]//$e.from)|clean)+":"+(($idmap[$e.to]//$e.to)|clean)),kind:$e.kind,from:($idmap[$e.from]//$e.from),to:($idmap[$e.to]//$e.to),repository:$repo,evidence:ev($e)}] as $edges
  | {schema_version:"3.0",ok:true,graph_hash:"pending",
     identity_policy:{version:"upg-v3-semantic-identity",path_rename_stable:true,unrelated_edit_stable:true,preferred_source:"logical repository/language/kind/component/name identity",collision_policy:"merge_same_logical_identity_with_provenance"},
     summary:{nodes:($nodes|length),edges:($edges|length),repositories:1,cross_repository_edges:([$edges[]|select(.kind|startswith("cross_repository"))]|length)},
     nodes:($nodes|sort_by(.id)),edges:($edges|sort_by(.id)),partitions:[],inputs:{semantic_graph_hash:.graph_hash}}
' "$tmp/semantic.json" > "$tmp/base.json"

jq '
  .nodes |= (group_by(.id) | map(. as $g | $g[0]
    | .evidence.provenance=([$g[].evidence.provenance[]?] | unique | sort)
    | .evidence.invalidation_keys=([$g[].evidence.invalidation_keys[]?] | unique | sort)
    | .source_ids=([$g[].source_id] | unique | sort)
    | del(.source_id)) | sort_by(.id))
  | .summary.nodes=(.nodes|length)
' "$tmp/base.json" > "$tmp/deduped.json"
mv "$tmp/deduped.json" "$tmp/base.json"

# Merge already-built peer graphs and connect matching public interfaces/contracts.
if [[ "${#PEER_GRAPHS[@]}" -gt 0 ]]; then
  jq -s '.' "${PEER_GRAPHS[@]}" > "$tmp/peers.json"
  jq --slurpfile peers "$tmp/peers.json" '
    ($peers[0] // []) as $peers
    | . as $local
    | ([$peers[].nodes[]?] | unique_by(.id)) as $peer_nodes
    | ([$peers[].edges[]?] | unique_by(.id)) as $peer_edges
    | ([
        $local.nodes[] as $a | $peer_nodes[] as $b
        | select($a.repository != $b.repository and $a.name != "" and $a.name == $b.name)
        | select(($a.kind|test("interface|contract|symbol")) and ($b.kind|test("interface|contract|symbol")))
        | {id:("upg-cross:"+$a.repository+":"+$b.repository+":"+$a.name),kind:"cross_repository_contract",from:$a.id,to:$b.id,repository:$a.repository,
           evidence:{class:"cross_repository",confidence:([$a.evidence.confidence,$b.evidence.confidence]|min),provenance:["unified_program_graph:semantic_name_join"],freshness:"current",invalidation_keys:([$a.id,$b.id]|sort)}}
      ] | unique_by(.id) | sort_by(.id)) as $cross
    | .nodes = ((.nodes + $peer_nodes)|unique_by(.id)|sort_by(.id))
    | .edges = ((.edges + $peer_edges + $cross)|unique_by(.id)|sort_by(.id))
    | .summary.nodes=(.nodes|length) | .summary.edges=(.edges|length)
    | .summary.repositories=([.nodes[].repository]|unique|length)
    | .summary.cross_repository_edges=($cross|length)
  ' "$tmp/base.json" > "$tmp/merged-peers.json"
  mv "$tmp/merged-peers.json" "$tmp/base.json"
fi

# Partition by entity kind. Each file is independently content-addressed and mergeable.
jq -r '([.nodes[].kind,.edges[].kind]|unique[])' "$tmp/base.json" | while IFS= read -r kind; do
  key="$(printf '%s' "$kind" | tr -c 'A-Za-z0-9._-' '_')"
  jq --arg kind "$kind" '{schema_version:"1.0",kind:$kind,nodes:[.nodes[]|select(.kind==$kind)],edges:[.edges[]|select(.kind==$kind)]}' "$tmp/base.json" > "$tmp/partition.json"
  hash="$(jq -S -c . "$tmp/partition.json" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
  jq --arg hash "$hash" '. + {hash:$hash}' "$tmp/partition.json" > "$PARTITIONS/$key.json"
done

jq -s '[.[]|{kind,hash,file:(.kind|gsub("[^A-Za-z0-9._-]";"_")+".json")}]|sort_by(.kind)' "$PARTITIONS"/*.json > "$tmp/partitions.json"
jq --slurpfile p "$tmp/partitions.json" '.partitions=$p[0]' "$tmp/base.json" > "$tmp/with-parts.json"
graph_hash="$(jq -S -c '{nodes,edges,partitions}' "$tmp/with-parts.json" | (sha256sum 2>/dev/null || shasum -a 256) | awk '{print $1}')"
jq --arg hash "$graph_hash" '.graph_hash=$hash' "$tmp/with-parts.json" > "$OUT"

if [[ "$JSON_OUT" == "1" ]]; then cat "$OUT"; else jq -r '"Unified Program Graph v3 nodes=\(.summary.nodes) edges=\(.summary.edges) partitions=\(.partitions|length)"' "$OUT"; fi
