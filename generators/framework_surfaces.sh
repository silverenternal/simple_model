#!/usr/bin/env bash
set -euo pipefail

ROOT="."
STRUCT="${STRUCT_FILE:-./struct.json}"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --root) ROOT="$2"; shift 2 ;;
    --struct|-s) STRUCT="$2"; shift 2 ;;
    --json) JSON_OUT=1; shift ;;
    -h|--help) echo "framework_surfaces.sh --root <repo> --struct <struct> [--json]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done
ROOT="$(cd "$ROOT" && pwd)"
[[ -f "$STRUCT" ]] || { echo "[FAIL] struct not found: $STRUCT" >&2; exit 2; }

tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
jq -c '.modules[]? as $m | $m.components[]? | {module:$m.name, component:.name, path:(.path // "")}' "$STRUCT" | while IFS= read -r c; do
  rel=$(jq -r '.path' <<<"$c")
  [[ -f "$ROOT/$rel" ]] || continue
  python3 - "$ROOT/$rel" "$c" >> "$tmp" <<'PY'
import hashlib, json, re, sys
path, comp_json = sys.argv[1], sys.argv[2]
c = json.loads(comp_json)
patterns = [
  ("express", re.compile(r'\b(?:app|router)\.(get|post|put|patch|delete)\s*\(\s*[\'"]([^\'"]+)')),
  ("fastapi", re.compile(r'@(?:app|router)\.(get|post|put|patch|delete)\s*\(\s*[\'"]([^\'"]+)')),
  ("django_flask", re.compile(r'@(?:app|bp|router)\.route\s*\(\s*[\'"]([^\'"]+)')),
  ("go_net_http", re.compile(r'\bHandleFunc\s*\(\s*[\'"]([^\'"]+)')),
]
try:
  lines = open(path, encoding="utf-8", errors="ignore").read().splitlines()
except OSError:
  lines = []
for i, line in enumerate(lines, 1):
  for fw, rx in patterns:
    m = rx.search(line)
    if not m:
      continue
    if fw in ("express", "fastapi"):
      method, route = m.group(1).upper(), m.group(2)
    else:
      method, route = "ANY", m.group(1)
    sig = f"{method} {route}"
    h = hashlib.sha256((path + ":" + sig).encode()).hexdigest()
    print(json.dumps({"framework": fw, "method": method, "path": route, "file": path, "line": i, "module": c["module"], "component": c["component"], "handler": "", "parser": "framework_surface_structural", "confidence": 0.78, "hash": h}, separators=(",", ":")))
PY
done
surfaces=$(jq -s '.' "$tmp")
report=$(jq -n --arg root "$ROOT" --arg struct "$STRUCT" --argjson surfaces "$surfaces" '{schema_version:"1.0", ok:true, root:$root, struct:$struct, summary:{surfaces:($surfaces|length), routes:($surfaces|length)}, surfaces:$surfaces}')
if [[ "$JSON_OUT" == "1" ]]; then printf '%s\n' "$report"; else jq -r '"Framework Surfaces routes=" + (.summary.routes|tostring)' <<<"$report"; fi
