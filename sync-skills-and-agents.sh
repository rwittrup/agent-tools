#!/usr/bin/env bash
# Sync local .cursor/skills, .cursor/agents, and .cursor/rules into Cursor/Claude
# paths. Agents and rules (and non-Cursor skill dests) use symlinks. Skills under
# ~/.cursor/skills are real directory copies so Cursor Cloud Agents can sync them
# (cloud sync only reads real dirs directly inside ~/.cursor/skills/).
#
# For ~/.cursor/skills: the destination is cleared, then each skill folder is
# copied. Other dests: idempotent symlinks (correct links left alone; wrong-target
# links removed and recreated).
#
# Default: quiet (errors only; one summary line if anything changed).
# Use -v / --verbose for per-entry logs. See --help.

set -euo pipefail

VERBOSE=0
created_count=0
replaced_count=0
skipped_count=0
copied_count=0

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="${REPO_ROOT}/.cursor/skills"
AGENTS_SRC="${REPO_ROOT}/.cursor/agents"
RULES_SRC="${REPO_ROOT}/.cursor/rules"

# Real copies (not symlinks) — required for Cursor Cloud Agent skill sync.
CURSOR_SKILLS_DEST="${HOME}/.cursor/skills"

# Symlink destinations for skills (cloud sync does not use these).
SKILL_SYMLINK_DEST_DIRS=(
  "${HOME}/.agents/skills"
  "${HOME}/.claude/skills"
)
AGENT_DEST_DIRS=(
  "${HOME}/.cursor/agents"
  "${HOME}/.claude/agents"
)
RULE_DEST_DIRS=(
  "${HOME}/.cursor/rules"
  "${HOME}/.claude/rules"
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
    .cursor/skills/*  →  ~/.cursor/skills/<name>  (real copy; dest cleared first)
                      →  ~/.agents/skills/<name>, ~/.claude/skills/<name>  (symlink)
    .cursor/agents/*  →  ~/.cursor/agents/<name>, ~/.claude/agents/<name>
    .cursor/rules/*   →  ~/.cursor/rules/<name>, ~/.claude/rules/<name>

  ~/.cursor/skills is wiped then re-copied so obsolete skills are removed and
  Cloud Agents see real directories (not symlinks).

  Wrong-target symlinks are replaced automatically (same name).

  Default: quiet — prints only errors, plus one line if anything changed.
  -v, --verbose  Log each check (unchanged, created, replaced, copied).
EOF
}

ensure_dir() {
  local d="$1"
  [[ -d "$d" ]] || mkdir -p "$d" || die "could not create directory: $d"
}

# Remove dest entirely and recreate empty, so obsolete skills are gone.
reset_dir() {
  local d="$1"
  if [[ -e "$d" ]]; then
    rm -rf "$d" || die "could not remove directory: $d"
  fi
  mkdir -p "$d" || die "could not create directory: $d"
  vlog "cleared: $d"
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
# Wrong-target symlinks are removed and recreated.
link_one() {
  local dest_parent="$1"
  local link_name="$2"
  local source_path="$3"
  local dest="${dest_parent}/${link_name}"
  local replaced=0

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
    vlog "replacing wrong symlink: $dest (was $current, want $source_abs)"
    rm "$dest" || die "could not remove symlink: $dest"
    replaced=1
  fi

  if [[ -e "$dest" ]]; then
    die "exists and is not a symlink: $dest"
  fi

  ln -s "$source_abs" "$dest" || die "ln -s failed: $dest"
  if [[ "$replaced" -eq 1 ]]; then
    ((replaced_count++)) || true
    vlog "replaced: $dest -> $source_abs"
  else
    ((created_count++)) || true
    vlog "created: $dest -> $source_abs"
  fi
}

# copy_one <dest_parent> <name> <source_path>
# Copies source into dest_parent/name as a real directory/file (not a symlink).
copy_one() {
  local dest_parent="$1"
  local name="$2"
  local source_path="$3"
  local dest="${dest_parent}/${name}"

  [[ -e "$source_path" ]] || die "source missing: $source_path"

  cp -R "$source_path" "$dest" || die "cp -R failed: $source_path -> $dest"
  ((copied_count++)) || true
  vlog "copied: $source_path -> $dest"
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
  [[ -d "$RULES_SRC" ]] || die "missing directory: $RULES_SRC"

  local d
  for d in "${SKILL_SYMLINK_DEST_DIRS[@]}" "${AGENT_DEST_DIRS[@]}" "${RULE_DEST_DIRS[@]}"; do
    ensure_dir "$d"
  done

  # Cloud Agents need real dirs under ~/.cursor/skills — wipe then copy.
  reset_dir "$CURSOR_SKILLS_DEST"

  shopt -s nullglob

  local name path
  for path in "${SKILLS_SRC}"/*; do
    name="$(basename "$path")"
    [[ "$name" == "." || "$name" == ".." ]] && continue
    copy_one "$CURSOR_SKILLS_DEST" "$name" "$path"
    for d in "${SKILL_SYMLINK_DEST_DIRS[@]}"; do
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

  for path in "${RULES_SRC}"/*; do
    name="$(basename "$path")"
    [[ "$name" == "." || "$name" == ".." ]] && continue
    for d in "${RULE_DEST_DIRS[@]}"; do
      link_one "$d" "$name" "$path"
    done
  done

  shopt -u nullglob

  if [[ "$VERBOSE" -eq 1 ]]; then
    echo "done."
  else
    if [[ "$created_count" -gt 0 ]] || [[ "$replaced_count" -gt 0 ]] || [[ "$copied_count" -gt 0 ]]; then
      echo "Sync: ${copied_count} skills copied to ~/.cursor/skills; symlinks: ${created_count} created, ${replaced_count} replaced (${skipped_count} already correct)."
    fi
  fi
}

main "$@"
