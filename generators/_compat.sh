#!/usr/bin/env bash
# generators/_compat.sh — Cross-platform compatibility layer
# All process substitutions replaced with temp files for Windows Git Bash compatibility.

# Detect Windows (Git Bash / MSYS2 / Cygwin)
is_windows() {
    [[ "${OS:-}" == "Windows_NT" ]] || \
    [[ "$(uname -s 2>/dev/null || true)" == MINGW* ]] || \
    [[ "$(uname -s 2>/dev/null || true)" == CYGWIN* ]]
}

export -f is_windows
