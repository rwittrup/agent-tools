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

# conflict_port LOG: the host port of a bind failure in LOG, or nothing. Matches both wordings Docker uses:
#   "Bind for 0.0.0.0:15301 failed: port is already allocated"
#   "failed to bind host port 0.0.0.0:15301/tcp: address already in use"
conflict_port() {
  grep -Eo 'Bind for [^ ]*:[0-9]+ failed: port is already allocated|failed to bind host port [^ ]*:[0-9]+/(tcp|udp): address already in use' "$1" 2>/dev/null \
    | head -n 1 | sed -E 's/.*:([0-9]+)( failed|\/(tcp|udp):).*/\1/'
}

# repair_port_conflict PORT: compose-ports.sh moves the mapping that failed to bind onto a free port (exit 0), so the
# gate can retry. It cannot move a port that follows PORT_OFFSET or one a non-compose process holds (exit 4).
repair_port_conflict() {
  bash "${SETUP_DIR}/compose-ports.sh" write --repair "$1"
}

# explain_port_conflict LOG: the repair did not apply. Say who holds the port and what is left to try.
explain_port_conflict() {
  local port holder
  port="$(conflict_port "$1")"
  [[ -n "${port}" ]] || return 0
  holder="$(docker ps --filter "publish=${port}" --format '{{.Names}} ({{.Status}})' | head -n 3 | tr '\n' ' ')"
  say "PORT CONFLICT: host port ${port} is held by: ${holder:-<not a container; see: lsof -nP -iTCP:${port} -sTCP:LISTEN>}"
  say "compose-ports.sh could not move it. If ${port} is one of this worktree's PORT_OFFSET ports (Rails API, databases,"
  say "Redpanda ...), pin another PORT_OFFSET in .env.local, delete .env and rerun worktree-setup.sh. Another worktree's"
  say "stack is never the thing to stop: every compose-published literal port is shifted off it."
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
