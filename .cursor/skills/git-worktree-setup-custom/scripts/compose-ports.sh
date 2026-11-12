#!/usr/bin/env bash
# Wrapper for compose-ports.py (isolated mode: no PYTHONPATH or cwd imports). Run from inside the worktree.
# See compose-ports.py for the commands: write, list, port, self-check.
exec python3 -I "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/compose-ports.py" "$@"
