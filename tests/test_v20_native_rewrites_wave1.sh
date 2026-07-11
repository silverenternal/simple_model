#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
for language in typescript python go rust; do
  case "$language" in
    typescript) source='function serve() { return 1; }'; ext='ts'; start=9; end=14 ;;
    python) source=$'def serve():\n    return 1\n'; ext='py'; start=4; end=9 ;;
    go) source='func serve() { return 1 }'; ext='go'; start=5; end=10 ;;
    rust) source='fn serve() -> i32 { 1 }'; ext='rs'; start=3; end=8 ;;
  esac
  root="$tmp/$language"; mkdir -p "$root"; printf '%s\n' "$source" > "$root/source.$ext"
  hash="$( (sha256sum "$root/source.$ext" 2>/dev/null || shasum -a 256 "$root/source.$ext") | awk '{print $1}')"
  jq -n --arg language "$language" --arg ext "$ext" --arg hash "$hash" --argjson start "$start" --argjson end "$end" '{schema_version:"1.0",language:$language,operation:"symbol_rename",source:("source."+$ext),source_hash:$hash,edits:[{id:"rename-serve",capture:{stable_id:("sym:"+$language+":serve"),start:$start,end:$end,expected_hash:$hash},original:"serve",replacement:"serve_new"}]}' > "$tmp/$language.json"
  bash generators/native_rewrite_dispatch.sh --root "$root" --spec "$tmp/$language.json" --output "$tmp/$language-sim.json" --simulate --json > "$tmp/$language-sim.stdout"
  jq -e --arg language "$language" '.ok and .native and .decision=="accept" and .language==$language and .checks.parse_after_write.status=="passed" and .checks.idempotency.status=="ready" and .checks.inverse.status=="ready"' "$tmp/$language-sim.json" >/dev/null
  key="$(jq -r '.idempotency_key' "$tmp/$language-sim.json")"
  bash generators/native_rewrite_dispatch.sh --root "$root" --spec "$tmp/$language.json" --output "$tmp/$language-apply.json" --apply --json >/dev/null
  jq -e '.status=="applied" and .native==true and (.output_hash|length)==64' "$tmp/$language-apply.json" >/dev/null
  grep -q 'serve_new' "$root/source.$ext"
  inverse="$(jq -r '.inverse_ir' "$tmp/$language-apply.json")"
  jq -e --arg language "$language" '.language==$language and (.inverse_of|length)==64' "$inverse" >/dev/null
  jq -n --argjson spec "$(cat "$tmp/$language.json")" --arg source "source.$ext" --arg hash "$(jq -r '.output_hash' "$tmp/$language-apply.json")" '. as $s | $spec | .source=$source | .source_hash=$hash' "$tmp/$language.json" >/dev/null
  test "$(jq -r '.idempotency_key' "$tmp/$language-apply.json")" = "$key"
  jq '.edits[0].replacement="serve_newer"' "$tmp/$language.json" > "$tmp/$language-malformed.json"
  if bash generators/native_rewrite_dispatch.sh --root "$root" --spec "$tmp/$language-malformed.json" --output "$tmp/bad.json" --simulate --json >/dev/null 2>&1; then exit 1; fi
done
jq -n '{schema_version:"1.0",language:"typescript",operation:"symbol_rename",mode:"text_fallback"}' > "$tmp/fallback.json"
bash generators/native_rewrite_dispatch.sh --root "$tmp/typescript" --spec "$tmp/fallback.json" --output "$tmp/fallback-report.json" --json >/dev/null
jq -e '.status=="review_only" and .native==false and .decision=="review_only"' "$tmp/fallback-report.json" >/dev/null
for language in typescript python go rust; do jq -e '.backend=="native" and (.operations|length)==6 and .fallback_policy=="review_only"' "codemods/backends/$language/backend.json" >/dev/null; done
echo "  [OK] native rewrite wave1 languages=4 round_trip=1"
