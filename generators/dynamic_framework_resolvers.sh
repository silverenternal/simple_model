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
    -h|--help) echo "dynamic_framework_resolvers.sh --root <repo> --struct <struct> [--json]"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; exit 64 ;;
  esac
done

command -v jq >/dev/null 2>&1 || { echo "[FAIL] missing jq" >&2; exit 2; }
[[ -d "$ROOT" && -f "$STRUCT" ]] || { echo "[FAIL] missing root or struct" >&2; exit 2; }
ROOT="$(cd "$ROOT" && pwd)"
STRUCT="$(cd "$(dirname "$STRUCT")" && pwd)/$(basename "$STRUCT")"

python3 - "$ROOT" "$STRUCT" "$JSON_OUT" <<'PY'
import ast
import hashlib
import json
import os
import re
import sys

root, struct_path, json_out = sys.argv[1], sys.argv[2], sys.argv[3] == "1"

with open(struct_path, encoding="utf-8") as f:
    struct = json.load(f)

components = {}
for mod in struct.get("modules", []):
    for comp in mod.get("components", []):
        rel = comp.get("path") or ""
        if rel:
            components[os.path.normpath(rel)] = {
                "module": mod.get("name", ""),
                "component": comp.get("name", ""),
                "path": rel,
            }

def relpath(path):
    return os.path.relpath(path, root)

def comp_for(rel):
    rel = os.path.normpath(rel)
    if rel in components:
        return components[rel]
    best = {"module": "", "component": "", "path": rel}
    for cpath, meta in components.items():
        if rel.endswith(cpath) or cpath.endswith(rel):
            return meta
    return best

def stable_id(kind, name, rel, line):
    raw = f"{kind}:{name}:{rel}:{line}"
    return re.sub(r"[^A-Za-z0-9_.:-]", "_", raw)[:180]

def digest(*parts):
    return hashlib.sha256(":".join(map(str, parts)).encode()).hexdigest()

def node(kind, name, rel, line, resolver, confidence, risk, evidence):
    meta = comp_for(rel)
    status = "unsafe" if risk == "dynamic_unsafe" else "probe_gap"
    if risk == "dynamic_known":
        status = "static_inferred"
    return {
        "id": stable_id(kind, name, rel, line),
        "kind": kind,
        "name": name,
        "path": rel,
        "line": int(line or 0),
        "module": meta.get("module", ""),
        "component": meta.get("component", ""),
        "resolver": resolver,
        "confidence": confidence,
        "risk_level": risk,
        "verification_status": status,
        "semantic_links": [],
        "evidence": evidence,
        "hash": digest(kind, name, rel, line, resolver),
    }

def py_name(expr):
    if isinstance(expr, ast.Name):
        return expr.id
    if isinstance(expr, ast.Attribute):
        parent = py_name(expr.value)
        return f"{parent}.{expr.attr}" if parent else expr.attr
    if isinstance(expr, ast.Call):
        return py_name(expr.func)
    return ""

def literal(expr):
    if isinstance(expr, ast.Constant) and isinstance(expr.value, (str, int, bool)):
        return str(expr.value)
    if isinstance(expr, ast.JoinedStr):
        return "<formatted-string>"
    return ""

nodes = []
source_ext = {".py", ".js", ".jsx", ".ts", ".tsx", ".go", ".rs", ".java", ".kt", ".rb", ".php", ".json", ".toml", ".yaml", ".yml"}
skip_dirs = {".git", "node_modules", "target", "dist", "build", ".venv", "__pycache__"}

for dirpath, dirnames, filenames in os.walk(root):
    rel_dir = os.path.relpath(dirpath, root)
    if rel_dir == "generated":
        dirnames[:] = []
        continue
    dirnames[:] = [d for d in dirnames if d not in skip_dirs]
    for filename in filenames:
        ext = os.path.splitext(filename)[1]
        if ext not in source_ext and filename not in {"package.json", "pyproject.toml"}:
            continue
        path = os.path.join(dirpath, filename)
        rel = relpath(path)
        try:
            if os.path.getsize(path) > 1024 * 1024:
                continue
            text = open(path, encoding="utf-8", errors="ignore").read()
        except OSError:
            continue
        lines = text.splitlines()

        if filename == "package.json":
            try:
                pkg = json.loads(text)
            except Exception:
                pkg = {}
            for field in ("main", "module", "bin"):
                if field in pkg:
                    nodes.append(node("plugin_registration", f"package.{field}:{pkg[field]}", rel, 1, "package_json_entrypoint", 0.93, "dynamic_known", {"field": field, "value": pkg[field]}))
            for key, val in (pkg.get("exports") or {}).items() if isinstance(pkg.get("exports"), dict) else []:
                nodes.append(node("plugin_registration", f"package.exports:{key}", rel, 1, "package_json_exports", 0.90, "dynamic_known", {"field": "exports", "key": key, "value": val}))
            continue

        if ext == ".py":
            try:
                tree = ast.parse(text)
            except SyntaxError:
                tree = None
            if tree:
                parents = {}
                for parent in ast.walk(tree):
                    for child in ast.iter_child_nodes(parent):
                        parents[child] = parent
                for item in ast.walk(tree):
                    if isinstance(item, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
                        for dec in getattr(item, "decorator_list", []):
                            call = dec if isinstance(dec, ast.Call) else None
                            dname = py_name(call.func if call else dec)
                            args = call.args if call else []
                            route = literal(args[0]) if args else ""
                            if re.search(r"(^|\.)(get|post|put|patch|delete|route)$", dname) and route:
                                method = dname.split(".")[-1].upper()
                                if method == "ROUTE":
                                    method = "ANY"
                                nodes.append(node("route", f"{method} {route}", rel, item.lineno, "python_decorator_ast", 0.96, "dynamic_known", {"decorator": dname, "handler": item.name}))
                            if re.search(r"(task|job|worker)$", dname):
                                nodes.append(node("job_registration", item.name, rel, item.lineno, "python_decorator_ast", 0.86, "dynamic_known", {"decorator": dname}))
                    if isinstance(item, ast.Call):
                        fname = py_name(item.func)
                        args = item.args
                        first = literal(args[0]) if args else ""
                        second = literal(args[1]) if len(args) > 1 else ""
                        if re.search(r"(container|injector|services?)\.(register|bind|provide)$", fname) and first:
                            nodes.append(node("di_binding", first, rel, item.lineno, "python_call_ast", 0.88, "dynamic_known", {"call": fname, "target": second}))
                        if re.search(r"(bus|events?|emitter)\.(on|subscribe|listen)$", fname) and first:
                            nodes.append(node("event_subscription", first, rel, item.lineno, "python_call_ast", 0.88, "dynamic_known", {"call": fname, "handler": second}))
                        if fname in {"importlib.import_module", "__import__"} or fname.endswith(".import_module"):
                            risk = "dynamic_unverified" if first else "dynamic_unsafe"
                            nodes.append(node("dynamic_import", first or "<dynamic-expression>", rel, item.lineno, "python_import_ast", 0.84 if first else 0.55, risk, {"call": fname}))
                        if fname in {"getattr", "setattr", "hasattr"}:
                            kind = "monkey_patch" if fname == "setattr" else "reflection"
                            risk = "dynamic_unsafe" if fname == "setattr" else "dynamic_unverified"
                            nodes.append(node(kind, first or fname, rel, item.lineno, "python_reflection_ast", 0.80, risk, {"call": fname}))

        for idx, line in enumerate(lines, 1):
            route_patterns = [
                ("express_router", r"\b(?:app|router)\.(get|post|put|patch|delete)\s*\(\s*['\"]([^'\"]+)"),
                ("fastify_route", r"\b(?:fastify|server)\.(get|post|put|patch|delete)\s*\(\s*['\"]([^'\"]+)"),
                ("nest_decorator", r"@(Get|Post|Put|Patch|Delete)\s*\(\s*['\"]([^'\"]*)"),
                ("go_net_http", r"\bhttp\.HandleFunc\s*\(\s*['\"]([^'\"]+)"),
                ("spring_mapping", r"@(GetMapping|PostMapping|PutMapping|PatchMapping|DeleteMapping|RequestMapping)\s*\(\s*['\"]([^'\"]+)"),
            ]
            for resolver, pattern in route_patterns:
                m = re.search(pattern, line)
                if not m:
                    continue
                if resolver in {"express_router", "fastify_route"}:
                    method, route = m.group(1).upper(), m.group(2)
                elif resolver == "go_net_http":
                    method, route = "ANY", m.group(1)
                elif resolver == "spring_mapping":
                    method = m.group(1).replace("Mapping", "").upper() or "ANY"
                    route = m.group(2)
                else:
                    method = m.group(1).upper()
                    route = "/" + m.group(2).strip("/") if m.group(2) else "/"
                nodes.append(node("route", f"{method} {route}", rel, idx, resolver, 0.84, "dynamic_known", {"line": line.strip()}))

            for resolver, pattern in [
                ("ts_di_container", r"\b(?:container|injector|services?)\.(?:register|bind|set)\s*\(\s*['\"]([^'\"]+)"),
                ("python_di_container", r"\b(?:container|injector|services?)\.(?:register|bind|provide)\s*\(\s*['\"]([^'\"]+)"),
            ]:
                m = re.search(pattern, line)
                if m:
                    nodes.append(node("di_binding", m.group(1), rel, idx, resolver, 0.78, "dynamic_known", {"line": line.strip()}))

            m = re.search(r"\b(?:bus|eventBus|emitter|events)\.(?:on|subscribe|listen)\s*\(\s*['\"]([^'\"]+)", line)
            if m:
                nodes.append(node("event_subscription", m.group(1), rel, idx, "event_bus_registration", 0.82, "dynamic_known", {"line": line.strip()}))

            m = re.search(r"\b(?:queue|worker|jobs)\.(?:process|register|addHandler)\s*\(\s*['\"]([^'\"]+)", line)
            if m:
                nodes.append(node("job_registration", m.group(1), rel, idx, "job_registration", 0.80, "dynamic_known", {"line": line.strip()}))

            m = re.search(r"\bimport\s*\(\s*([^)]*)\)", line)
            if m and ext in {".js", ".jsx", ".ts", ".tsx"}:
                expr = m.group(1).strip()
                lit = re.match(r"['\"]([^'\"]+)['\"]", expr)
                nodes.append(node("dynamic_import", lit.group(1) if lit else "<dynamic-expression>", rel, idx, "js_dynamic_import", 0.83 if lit else 0.56, "dynamic_unverified" if lit else "dynamic_unsafe", {"expression": expr}))

            m = re.search(r"\brequire\s*\(\s*([^)]*)\)", line)
            if m and ext in {".js", ".jsx", ".ts", ".tsx"}:
                expr = m.group(1).strip()
                if not re.match(r"['\"][^'\"]+['\"]", expr):
                    nodes.append(node("dynamic_import", "<dynamic-require>", rel, idx, "js_dynamic_require", 0.55, "dynamic_unsafe", {"expression": expr}))

            if re.search(r"\b(eval|Function)\s*\(", line) and ext in {".js", ".jsx", ".ts", ".tsx"}:
                nodes.append(node("unsafe_execution", "eval-like execution", rel, idx, "js_eval_scan", 0.90, "dynamic_unsafe", {"line": line.strip()}))
            if re.search(r"\.prototype\.[A-Za-z_$][\w$]*\s*=", line):
                nodes.append(node("monkey_patch", "prototype mutation", rel, idx, "prototype_mutation_scan", 0.86, "dynamic_unsafe", {"line": line.strip()}))
            if re.search(r"\bplugin\.Open\s*\(", line) and ext == ".go":
                nodes.append(node("dynamic_import", "go plugin.Open", rel, idx, "go_plugin_scan", 0.85, "dynamic_unverified", {"line": line.strip()}))
            if re.search(r"\breflect\.", line) and ext == ".go":
                nodes.append(node("reflection", "go reflect", rel, idx, "go_reflect_scan", 0.76, "dynamic_unverified", {"line": line.strip()}))
            if re.search(r"\blibloading::|Library::new", line) and ext == ".rs":
                nodes.append(node("dynamic_import", "rust dynamic library", rel, idx, "rust_dynamic_loading_scan", 0.78, "dynamic_unverified", {"line": line.strip()}))

seen = {}
unique = []
for n in nodes:
    key = (n["kind"], n["name"], n["path"], n["line"], n["resolver"])
    if key not in seen:
        seen[key] = True
        unique.append(n)
unique.sort(key=lambda n: (n["path"], n["line"], n["kind"], n["name"]))

summary = {
    "nodes": len(unique),
    "routes": sum(1 for n in unique if n["kind"] == "route"),
    "di_bindings": sum(1 for n in unique if n["kind"] == "di_binding"),
    "plugin_registrations": sum(1 for n in unique if n["kind"] == "plugin_registration"),
    "event_subscriptions": sum(1 for n in unique if n["kind"] == "event_subscription"),
    "dynamic_imports": sum(1 for n in unique if n["kind"] == "dynamic_import"),
    "dynamic_known": sum(1 for n in unique if n["risk_level"] == "dynamic_known"),
    "dynamic_unverified": sum(1 for n in unique if n["risk_level"] == "dynamic_unverified"),
    "dynamic_unsafe": sum(1 for n in unique if n["risk_level"] == "dynamic_unsafe"),
}
report = {"schema_version": "1.0", "ok": True, "root": root, "struct": struct_path, "summary": summary, "nodes": unique}
print(json.dumps(report, indent=2 if not json_out else None, sort_keys=True))
PY
