#!/usr/bin/env bash
set -euo pipefail
ROOT="."; PATCH=""; PROFILE=""; OUT="generated/intelligence/patch-plan.json"; JSON_OUT=0; OVERRIDE=0
while [[ $# -gt 0 ]]; do
  case "$1" in --root) ROOT="$2"; shift 2 ;; --patch) PATCH="$2"; shift 2 ;; --profile) PROFILE="$2"; shift 2 ;; --output|-o) OUT="$2"; shift 2 ;; --allow-protected) OVERRIDE=1; shift ;; --json) JSON_OUT=1; shift ;; *) echo "unknown arg: $1" >&2; exit 64 ;; esac
done
[[ -f "$PATCH" ]] || { echo "--patch JSON is required" >&2; exit 64; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
if [[ -z "$PROFILE" ]]; then PROFILE="$tmp/style.json"; bash "$(dirname "$0")/style_profile.sh" --root "$ROOT" --output "$PROFILE" --json >/dev/null; fi
jq -e 'type=="object" and .schema_version=="1.0" and (.edits|type)=="array" and all(.edits[]; (.source|type)=="string" and (.start_line|type)=="number" and (.end_line|type)=="number" and .start_line>=1 and .end_line>=.start_line)' "$PATCH" >/dev/null || { echo "malformed patch spec" >&2; exit 3; }
jq -n --slurpfile profile "$PROFILE" --slurpfile patch "$PATCH" --argjson override "$OVERRIDE" '
  ($profile[0].files) as $profiles | ($patch[0].edits) as $edits
  | [ $edits[] | . as $e | ($profiles[] | select(.path==$e.source)) as $p | ($p.protected or $p.generated or $p.vendored or $p.ignored) as $blocked | {edit:$e,profile:$p,blocked:($blocked and ($override==0))} ] as $classified
  | [ $classified[] | select(.blocked) | {id:.edit.id,source:.edit.source,reason:(if .profile.protected then "protected" elif .profile.generated then "generated" elif .profile.vendored then "vendored" else "ignored" end)} ] as $blocked
  | [ $classified[] | select(.blocked|not) | .edit.source ] | unique as $sources
  | [ $sources[] as $source | ($classified | map(select((.blocked|not) and .edit.source==$source))) as $items
      | ([ $items[].edit | range(.start_line; (.end_line+1)) ] | unique | sort) as $lines
      | ($items | map(.edit.semantic_lines // ((.edit.end_line-.edit.start_line)+1)) | add) as $semantic
      | {source:$source,language:($items[0].profile.language),formatter:($items[0].profile.formatter),edits:[$items[].edit.id],touched_lines:($lines|length),line_ranges:($items|map({start:.edit.start_line,end:.edit.end_line})),semantic_lines:$semantic,unnecessary_lines:((($lines|length)-$semantic)|if .<0 then 0 else . end),formatter_scope:{start_line:($lines|min),end_line:($lines|max),mode:"changed_syntax_only"},conflict_risk:(if ($items|length)>1 then 0.35 else 0.1 end)} ] as $files
  | ($files | map(.unnecessary_lines) | add // 0) as $unnecessary | ($files | map(.touched_lines) | add // 0) as $touched
  | {schema_version:"1.0",ok:true,files:($files|sort_by(.source)),blocked_edits:$blocked,alternatives:[{name:"low-conflict-serial",order:($files|sort_by(.conflict_risk,.source)|map(.source)),reason:"apply one file at a time in lowest conflict-risk order"},{name:"semantic-batches",order:($files|group_by(.language)|map(sort_by(.source)|map(.source))),reason:"batch only language-compatible formatter scopes"}],summary:{selected_files:($files|length),blocked_edits:($blocked|length),protected_region_writes:([ $blocked[]|select(.reason=="protected")]|length),unnecessary_line_change_ratio:(if $touched==0 then 0 else ($unnecessary/$touched) end),conflict_risk:(if ($files|length)==0 then 0 else (($files|map(.conflict_risk)|add)/($files|length)) end),formatter_scopes:($files|map(.formatter_scope))},policy:{protected_default:true,override:$override,generated_default_block:true,vendored_default_block:true,ignored_default_block:true}}' > "$OUT"
if [[ "$JSON_OUT" == 1 ]]; then cat "$OUT"; else jq -r '"Patch plan files=\(.summary.selected_files) blocked=\(.summary.blocked_edits) unnecessary_ratio=\(.summary.unnecessary_line_change_ratio)"' "$OUT"; fi
jq -e '.ok==true' "$OUT" >/dev/null
