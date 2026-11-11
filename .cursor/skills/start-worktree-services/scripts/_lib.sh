#!/usr/bin/env bash
# Shared helpers for the start-worktree-services scripts. Sourced, not run.
# Resolves the worktree from the caller's cwd, so run the scripts from inside it.

SWS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# git-worktree-setup-custom owns ports, .env and Dispatch; this skill drives it.
SETUP_DIR="$(cd "${SWS_DIR}/../../git-worktree-setup-custom/scripts" && pwd)"

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "${ROOT_DIR}"

# Logs: set GATE_LOG_DIR to a scratchpad so they sit beside the session's other temp files.
LOG_DIR="${GATE_LOG_DIR:-${TMPDIR:-/tmp}/start-worktree-services/$(basename "${ROOT_DIR}")}"
mkdir -p "${LOG_DIR}"

say() { printf '%s\n' "$*" >&2; }

# worktree_env: this worktree's ports and project name, exactly as worktree-setup.sh resolves them.
# `just` run from the main checkout exports its own values, so drop those first.
worktree_env() {
  eval "$(bash "${SETUP_DIR}/worktree-env.sh" --unset)"
  eval "$(bash "${SETUP_DIR}/worktree-env.sh" --export)"
}

# running_services: compose services of this worktree that are running, one per line.
running_services() { docker compose ps --status running --services 2>/dev/null | sort; }

# missing_services SVC...: those not running, one per line.
missing_services() {
  local running svc
  running="$(running_services)"
  for svc in "$@"; do
    printf '%s\n' "${running}" | grep -qx "${svc}" || printf '%s\n' "${svc}"
  done
}

# env_secret_sha: first 12 hex of sha256(.env's GOOGLE_CLIENT_SECRET); never prints the value.
env_secret_sha() {
  local v
  v="$(grep -E '^GOOGLE_CLIENT_SECRET=' .env | tail -n 1 | sed 's/^[^=]*=//; s/^"//; s/"$//')"
  printf %s "${v}" | shasum -a 256 | cut -c1-12
}

# explain_port_conflict LOG: when LOG holds "Bind for ...:PORT failed: port is already allocated", say which
# container holds PORT. Some host ports (otelcol's 514, for one) are not offset per worktree, so two worktrees'
# stacks collide. The holder is usually another worktree's live stack: report it, never stop it.
explain_port_conflict() {
  local port holder
  port="$(grep -Eo 'Bind for [^ ]*:[0-9]+ failed: port is already allocated' "$1" 2>/dev/null | head -n 1 | sed -E 's/.*:([0-9]+) failed.*/\1/')"
  [[ -n "${port}" ]] || return 0
  holder="$(docker ps --filter "publish=${port}" --format '{{.Names}} ({{.Status}})' | head -n 3 | tr '\n' ' ')"
  say "PORT CONFLICT: host port ${port} is held by: ${holder:-<not a container; see: lsof -nP -iTCP:${port} -sTCP:LISTEN>}"
  say "That is usually another worktree's running stack. Do not stop it unless the user says so;"
  say "ask them to stop it (from that worktree: just dc-stop), then rerun."
}

# wait_http URL CODE SECONDS: poll until URL answers CODE.
wait_http() {
  local url="$1" want="$2" secs="$3" end got
  end=$(( $(date +%s) + secs ))
  while :; do
    got="$(curl -s -o /dev/null -w '%{http_code}' "${url}" 2>/dev/null || true)"
    [[ "${got}" == "${want}" ]] && return 0
    [[ "$(date +%s)" -ge "${end}" ]] && return 1
    sleep 3
  done
}
