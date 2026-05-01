#!/usr/bin/env bash
# Sync local .cursor/skills and .cursor/agents into Cursor/Claude agent paths via symlinks.
# For each entry under .cursor/skills/ and .cursor/agents/, ensures a symlink exists in the
# corresponding home directories pointing at this repo. Idempotent: correct
# symlinks are left unchanged; missing symlinks are created.
#
# If you previously symlinked from ./skills or ./agents and see "exists but points elsewhere",
# remove the stale symlink under ~/.agents/skills, ~/.cursor/skills, ~/.cursor/agents, or
# ~/.claude/agents and run this script again.
#
# Default: quiet (errors only; one summary line if anything was created).
# Use -v / --verbose for per-symlink logs. See --help.

set -euo pipefail

VERBOSE=0
created_count=0
skipped_count=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="${REPO_ROOT}/.cursor/skills"
AGENTS_SRC="${REPO_ROOT}/.cursor/agents"

SKILL_DEST_DIRS=(
  "${HOME}/.agents/skills"
  "${HOME}/.cursor/skills"
)
AGENT_DEST_DIRS=(
  "${HOME}/.cursor/agents"
  "${HOME}/.claude/agents"
)

die() {
  echo "error: $*" >&2
  exit 1
}

vlog() {
  [[ "$VERBOSE" -eq 1 ]] || return 0
  echo "$*"
}

usage() {
  cat <<'EOF'
Usage: sync-skills-and-agents.sh [-v|--verbose]

  Sources (repo root = directory containing this script):
    .cursor/skills/*  →  ~/.agents/skills/<name>, ~/.cursor/skills/<name>
    .cursor/agents/*  →  ~/.cursor/agents/<name>, ~/.claude/agents/<name>

  Default: quiet — prints only errors, plus one line if new symlinks were created.
  -v, --verbose  Log each symlink check (unchanged and created).
EOF
}

ensure_dir() {
  local d="$1"
  [[ -d "$d" ]] || mkdir -p "$d" || die "could not create directory: $d"
}

# Canonical absolute path (resolves symlinks). Requires python3.
realpath_canon() {
  python3 -c "import os, sys; print(os.path.realpath(sys.argv[1]))" "$1"
}

# If path is a symlink, print its resolved target; else empty.
read_symlink_target() {
  local p="$1"
  if [[ -L "$p" ]]; then
    realpath_canon "$p"
  else
    echo ""
  fi
}

# link_one <dest_parent> <link_name> <source_path>
# source_path must exist. Creates dest_parent/link_name -> source (absolute).
link_one() {
  local dest_parent="$1"
  local link_name="$2"
  local source_path="$3"
  local dest="${dest_parent}/${link_name}"

  [[ -e "$source_path" ]] || die "source missing: $source_path"

  local source_abs
  source_abs="$(realpath_canon "$source_path")"

  if [[ -L "$dest" ]]; then
    local current
    current="$(read_symlink_target "$dest")"
    if [[ "$current" == "$source_abs" ]]; then
      ((skipped_count++)) || true
      vlog "ok (already linked): $dest -> $source_abs"
      return 0
    fi
    die "exists but points elsewhere: $dest -> $current (expected $source_abs)"
  fi

  if [[ -e "$dest" ]]; then
    die "exists and is not a symlink: $dest"
  fi

  ln -s "$source_abs" "$dest" || die "ln -s failed: $dest"
  ((created_count++)) || true
  vlog "created: $dest -> $source_abs"
}

main() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -v | --verbose)
        VERBOSE=1
        shift
        ;;
      -h | --help)
        usage
        exit 0
        ;;
      *)
        die "unknown option: $1 (try --help)"
        ;;
    esac
  done

  [[ -d "$SKILLS_SRC" ]] || die "missing directory: $SKILLS_SRC"
  [[ -d "$AGENTS_SRC" ]] || die "missing directory: $AGENTS_SRC"

  local d
  for d in "${SKILL_DEST_DIRS[@]}" "${AGENT_DEST_DIRS[@]}"; do
    ensure_dir "$d"
  done

  shopt -s nullglob

  local name path
  for path in "${SKILLS_SRC}"/*; do
    name="$(basename "$path")"
    [[ "$name" == "." || "$name" == ".." ]] && continue
    for d in "${SKILL_DEST_DIRS[@]}"; do
      link_one "$d" "$name" "$path"
    done
  done

  for path in "${AGENTS_SRC}"/*; do
    name="$(basename "$path")"
    [[ "$name" == "." || "$name" == ".." ]] && continue
    for d in "${AGENT_DEST_DIRS[@]}"; do
      link_one "$d" "$name" "$path"
    done
  done

  shopt -u nullglob

  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "done."
  else
    if [[ "$created_count" -gt 0 ]]; then
      echo "Created ${created_count} symlink(s) (${skipped_count} already correct)."
    fi
  fi
}

main "$@"
