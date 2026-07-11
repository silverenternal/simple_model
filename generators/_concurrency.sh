#!/usr/bin/env bash
set -euo pipefail

sm_sha256_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk '{print $1}'
  else
    shasum -a 256 "$1" | awk '{print $1}'
  fi
}

sm_sha256_text() {
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s' "$1" | sha256sum | awk '{print $1}'
  else
    printf '%s' "$1" | shasum -a 256 | awk '{print $1}'
  fi
}

sm_atomic_write() {
  local target="$1" tmp
  mkdir -p "$(dirname "$target")"
  tmp="$(mktemp "$(dirname "$target")/.tmp.XXXXXX")"
  cat > "$tmp"
  mv "$tmp" "$target"
}

sm_lock_acquire() {
  local lock="$1" ttl="${2:-900}" now owner
  now="$(date +%s)"
  mkdir -p "$(dirname "$lock")"
  if mkdir "$lock" 2>/dev/null; then
    printf '%s\n' "$now" > "$lock/created_at"
    printf '%s\n' "$$" > "$lock/pid"
    return 0
  fi
  if [[ -f "$lock/created_at" ]]; then
    owner="$(cat "$lock/created_at" 2>/dev/null || echo 0)"
    if [[ "$owner" =~ ^[0-9]+$ ]] && (( now - owner > ttl )); then
      rm -rf "$lock"
      mkdir "$lock"
      printf '%s\n' "$now" > "$lock/created_at"
      printf '%s\n' "$$" > "$lock/pid"
      return 0
    fi
  fi
  return 1
}

sm_lock_release() {
  local lock="$1"
  [[ -d "$lock" ]] && rm -rf "$lock"
}

sm_write_set_conflicts() {
  jq -n --argjson tasks "$1" '
    [
      range(0; $tasks|length) as $i
      | range($i + 1; $tasks|length) as $j
      | ($tasks[$i]) as $a
      | ($tasks[$j]) as $b
      | (($a.outputs // []) + ($a.writes // [])) as $aw
      | (($b.outputs // []) + ($b.writes // [])) as $bw
      | [ $aw[]? as $x | $bw[]? | select(. == $x) ] as $same
      | select(($same|length) > 0)
      | {a:$a.id, b:$b.id, paths:$same}
    ]'
}
