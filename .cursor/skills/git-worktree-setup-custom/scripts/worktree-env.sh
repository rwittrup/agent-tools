#!/usr/bin/env bash

# Worktree environment and port offset resolver for Prepared911 Docker stacks.
#
# Generates isolated COMPOSE_PROJECT_NAME and non-colliding host ports for
# git worktrees, enabling developers to run multiple Docker stacks in parallel.
#
# Custom copy of the repo's dev/scripts/worktree-env.sh (adds DISPATCH_PORT; skips
# Chrome-blocked ports). Run from inside the worktree.
#
# Usage:
#   worktree-env.sh [--dotenv | --export | --status | --pin | --unset | --keys | --self-check]
#
# Output modes:
#   --dotenv       Output KEY="value" lines (for appending to .env)
#   --export       Output export KEY="value" lines (for eval in shell)
#   --status       Print human-readable summary of worktree stack configuration
#   --pin          Append missing COMPOSE_PROJECT_NAME / PORT_OFFSET pins to .env.local
#                  (linked worktrees only; offset is the lowest free multiple of 100
#                  not pinned by a sibling worktree and whose browser-facing ports
#                  Chrome allows)
#   --unset        Output `unset KEY ...` for every managed key (for eval, to drop
#                  values a parent `just` exported from the main checkout's .env)
#   --keys         Print every managed key, one per line
#   --self-check   Run internal assertions for CI/verification
#   (default)      Same as --dotenv

set -euo pipefail

# Lives outside the repo (agent-tools), so resolve the worktree from the caller's cwd.
ROOT_DIR="$(git rev-parse --show-toplevel)"

MODE="${1:---dotenv}"

# Every key emitted by --dotenv / --export (--self-check guards against drift).
MANAGED_KEYS=(
  COMPOSE_PROJECT_NAME PORT_OFFSET
  RAILS_API_PORT DISPATCH_PORT RAILS_DB_PORT RAILS_DB_REPLICA_PORT RAILS_REDIS_PORT
  REDPANDA_KAFKA_PORT REDPANDA_ADMIN_PORT REDPANDA_SCHEMA_PORT REDPANDA_CONSOLE_PORT
  APPS_DB_PORT LOCATIONS_DB_PORT APPS_REDIS_PORT ELASTIC_MQ_PORT ELASTIC_MQ_UI_PORT
  REDPANDA_BROKER
)

git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
git_common_dir="$(git rev-parse --git-common-dir 2>/dev/null || true)"
toplevel="$(git rev-parse --show-toplevel 2>/dev/null || echo "${ROOT_DIR}")"

is_linked_worktree=0
if [[ -n "${git_dir}" && -n "${git_common_dir}" && "${git_dir}" != "${git_common_dir}" ]]; then
  is_linked_worktree=1
fi

# read_env_local KEY [file]: last KEY=value in file (default .env.local), unquoted; empty if absent.
read_env_local() {
  local file="${2:-${ROOT_DIR}/.env.local}"
  [[ -f "${file}" ]] || return 0
  grep -E "^\s*$1=" "${file}" 2>/dev/null | tail -n 1 | cut -d'=' -f2- | tr -d '"'\'' ' || true
}

# Ports Chromium refuses to connect to (ERR_UNSAFE_PORT), at or above 1024.
# Source: kRestrictedPorts in net/base/port_util.cc. A browser-facing service on one of
# these looks healthy to curl, but Dispatch shows "Failed to fetch" and Google sign-in
# shows "Login error. Try again or contact support."
CHROMIUM_UNSAFE_PORTS=" 1719 1720 1723 2049 3659 4045 5060 5061 6000 6566 6665 6666 6667 6668 6669 6697 10080 "

# unsafe_port_for_offset OFFSET: prints "<service> <port>" for the first browser-facing
# service the offset would put on a Chromium-restricted port; prints nothing when safe.
unsafe_port_for_offset() {
  local offset="$1" entry name port
  for entry in "Rails API:3000" "Redpanda Admin API:19644" "Redpanda Schema Reg:18081" \
               "Redpanda Console:8888" "ElasticMQ UI:9325" "Dispatch:3002"; do
    name="${entry%:*}"
    port=$(( ${entry##*:} + offset ))
    if [[ "${CHROMIUM_UNSAFE_PORTS}" == *" ${port} "* ]]; then
      echo "${name} ${port}"
      return 0
    fi
  done
}

worktree_index=1
if [[ "${is_linked_worktree}" -eq 1 ]]; then
  detected_index="$(git worktree list --porcelain 2>/dev/null | grep '^worktree ' | cut -d' ' -f2- | grep -nx "${toplevel}" | cut -d: -f1 || true)"
  if [[ -n "${detected_index}" ]]; then
    worktree_index="${detected_index}"
  else
    worktree_index=2
  fi
fi

# Worktrees under .worktrees/ sit inside the main checkout, so `just` (dotenv-load
# searches ancestors) loads the main checkout's .env when the worktree has none, exporting
# its COMPOSE_PROJECT_NAME and PORT_OFFSET. Decide by provenance, not value: with no
# ${toplevel}/.env the environment can only hold an ancestor's values, so drop them. With
# its own .env, the values came from it (or a deliberate export) and are honored.
inherited_project="${COMPOSE_PROJECT_NAME:-}"
if [[ "${is_linked_worktree}" -eq 1 && ! -f "${toplevel}/.env" ]]; then
  unset COMPOSE_PROJECT_NAME PORT_OFFSET
fi

# Check for overrides in .env.local if not already exported in environment
if [[ -z "${PORT_OFFSET:-}" ]]; then
  PORT_OFFSET="$(read_env_local PORT_OFFSET)"
fi
if [[ -z "${COMPOSE_PROJECT_NAME:-}" ]]; then
  COMPOSE_PROJECT_NAME="$(read_env_local COMPOSE_PROJECT_NAME)"
fi

# Determine default port offset: main worktree = 0, linked worktrees = (index - 1) * 100
if [[ -z "${PORT_OFFSET:-}" ]]; then
  if [[ "${is_linked_worktree}" -eq 1 && "${worktree_index}" -ge 2 ]]; then
    PORT_OFFSET=$(( (worktree_index - 1) * 100 ))
  else
    PORT_OFFSET=0
  fi
fi

# Default Compose project name: apps-<sanitized worktree dir name>
default_project_name() {
  local dir_name
  dir_name="$(basename "${toplevel}")"
  printf 'apps-%s' "$(printf "%s" "${dir_name}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9_-' '-' | sed 's/^-//;s/-$//')"
}

# --pin: write this worktree's stack identity to .env.local so it survives later runs.
if [[ "${MODE}" == "--pin" ]]; then
  if [[ "${is_linked_worktree}" -ne 1 ]]; then
    echo "worktree-env: --pin is only valid in a linked worktree" >&2
    exit 1
  fi
  touch "${ROOT_DIR}/.env.local"
  if [[ -z "$(read_env_local COMPOSE_PROJECT_NAME)" ]]; then
    printf 'COMPOSE_PROJECT_NAME=%s\n' "$(default_project_name)" >> "${ROOT_DIR}/.env.local"
  fi
  if [[ -z "$(read_env_local PORT_OFFSET)" ]]; then
    taken=" "
    while read -r wt; do
      [[ "${wt}" == "${ROOT_DIR}" ]] && continue
      for f in "${wt}/.env.local" "${wt}/.env"; do
        offset="$(read_env_local PORT_OFFSET "${f}")"
        [[ -n "${offset}" ]] && taken="${taken}${offset} "
      done
    done < <(git worktree list --porcelain | sed -n 's/^worktree //p')
    offset=100
    while [[ "${taken}" == *" ${offset} "* || -n "$(unsafe_port_for_offset "${offset}")" ]]; do
      offset=$((offset + 100))
    done
    printf 'PORT_OFFSET=%s\n' "${offset}" >> "${ROOT_DIR}/.env.local"
  fi
  exit 0
fi

# Determine default Compose project name
if [[ -z "${COMPOSE_PROJECT_NAME:-}" ]]; then
  if [[ "${is_linked_worktree}" -eq 1 || "${PORT_OFFSET}" -gt 0 ]]; then
    COMPOSE_PROJECT_NAME="$(default_project_name)"
  else
    COMPOSE_PROJECT_NAME="apps"
  fi
fi

# Calculate host ports
RAILS_API_PORT=$(( 3000 + PORT_OFFSET ))
DISPATCH_PORT=$(( 3002 + PORT_OFFSET ))
RAILS_DB_PORT=$(( 5432 + PORT_OFFSET ))
RAILS_DB_REPLICA_PORT=$(( 5433 + PORT_OFFSET ))
RAILS_REDIS_PORT=$(( 6379 + PORT_OFFSET ))
REDPANDA_KAFKA_PORT=$(( 19092 + PORT_OFFSET ))
REDPANDA_ADMIN_PORT=$(( 19644 + PORT_OFFSET ))
REDPANDA_SCHEMA_PORT=$(( 18081 + PORT_OFFSET ))
REDPANDA_CONSOLE_PORT=$(( 8888 + PORT_OFFSET ))
APPS_DB_PORT=$(( 5434 + PORT_OFFSET ))
LOCATIONS_DB_PORT=$(( 5435 + PORT_OFFSET ))
APPS_REDIS_PORT=$(( 6380 + PORT_OFFSET ))
ELASTIC_MQ_PORT=$(( 9324 + PORT_OFFSET ))
ELASTIC_MQ_UI_PORT=$(( 9325 + PORT_OFFSET ))

# A linked worktree is on the wrong stack (shown as a --status warning) when it has no .env of its own (just would
# load the main checkout's, so any inherited project is the main checkout's) or the environment
# names a project other than the resolved one.
stack_problem=""
if [[ "${is_linked_worktree}" -eq 1 ]]; then
  if [[ ! -f "${toplevel}/.env" ]]; then
    stack_problem="${toplevel}/.env does not exist"
  elif [[ -n "${inherited_project}" && "${inherited_project}" != "${COMPOSE_PROJECT_NAME}" ]]; then
    stack_problem="environment has COMPOSE_PROJECT_NAME=${inherited_project}, expected ${COMPOSE_PROJECT_NAME}"
  fi
fi

case "${MODE}" in
  --self-check)
    # Self-check validation
    if [[ "${PORT_OFFSET}" -lt 0 ]]; then
      echo "worktree-env: self-check failed: PORT_OFFSET cannot be negative" >&2
      exit 1
    fi
    if [[ -z "${COMPOSE_PROJECT_NAME}" ]]; then
      echo "worktree-env: self-check failed: COMPOSE_PROJECT_NAME cannot be empty" >&2
      exit 1
    fi
    if [[ -z "$(unsafe_port_for_offset 3000)" ]]; then
      echo "worktree-env: self-check failed: offset 3000 (Rails API on 6000) not flagged unsafe" >&2
      exit 1
    fi
    for offset in $(seq 100 100 5000); do
      [[ "${offset}" -eq 3000 ]] && continue
      if [[ -n "$(unsafe_port_for_offset "${offset}")" ]]; then
        echo "worktree-env: self-check failed: offset ${offset} unexpectedly flagged unsafe" >&2
        exit 1
      fi
    done
    dotenv_out="$(bash "${BASH_SOURCE[0]}" --dotenv)"
    for key in "${MANAGED_KEYS[@]}"; do
      if ! grep -q "^${key}=" <<<"${dotenv_out}"; then
        echo "worktree-env: self-check failed: MANAGED_KEYS entry ${key} missing from --dotenv" >&2
        exit 1
      fi
    done
    echo "worktree-env --self-check ok (project=${COMPOSE_PROJECT_NAME}, offset=${PORT_OFFSET})"
    exit 0
    ;;

  --status|--info)
    echo "=== Worktree Docker Stack Configuration ==="
    echo "Worktree Path:        ${toplevel}"
    if [[ "${is_linked_worktree}" -eq 1 ]]; then
      echo "Worktree Type:        Linked Worktree (Index ${worktree_index})"
    else
      echo "Worktree Type:        Main Worktree (Primary)"
    fi
    echo "Compose Project:      ${COMPOSE_PROJECT_NAME}"
    echo "Port Offset:          +${PORT_OFFSET}"
    echo "--- Published Host Ports ---"
    echo "Rails API:            http://localhost:${RAILS_API_PORT}"
    echo "Dispatch UI:          http://localhost:${DISPATCH_PORT}"
    echo "Rails Primary DB:     localhost:${RAILS_DB_PORT}"
    echo "Rails Read Replica:   localhost:${RAILS_DB_REPLICA_PORT}"
    echo "Rails Redis:          localhost:${RAILS_REDIS_PORT}"
    echo "Redpanda Kafka:       localhost:${REDPANDA_KAFKA_PORT}"
    echo "Redpanda Admin API:   http://localhost:${REDPANDA_ADMIN_PORT}"
    echo "Redpanda Schema Reg:  http://localhost:${REDPANDA_SCHEMA_PORT}"
    echo "Redpanda Console:     http://localhost:${REDPANDA_CONSOLE_PORT}"
    echo "Apps DB:              localhost:${APPS_DB_PORT}"
    echo "Locations DB:         localhost:${LOCATIONS_DB_PORT}"
    echo "Apps Redis:           localhost:${APPS_REDIS_PORT}"
    echo "ElasticMQ (SQS):      http://localhost:${ELASTIC_MQ_PORT}"
    echo "ElasticMQ UI:         http://localhost:${ELASTIC_MQ_UI_PORT}"
    unsafe_port="$(unsafe_port_for_offset "${PORT_OFFSET}")"
    if [[ -n "${unsafe_port}" ]]; then
      echo "WARNING: ${unsafe_port% *} is on port ${unsafe_port##* }, which Chrome blocks (ERR_UNSAFE_PORT); remove PORT_OFFSET from .env.local, delete .env, and re-run: bash ~/.claude/skills/git-worktree-setup-custom/scripts/worktree-setup.sh"
    fi
    if [[ "${is_linked_worktree}" -eq 1 ]]; then
      dispatch_api="$(read_env_local API_BASE_URL "${toplevel}/turbo/apps/dispatch/.env.local.local")"
      if [[ "${dispatch_api##*:}" != "${RAILS_API_PORT}" ]]; then
        echo "WARNING: Dispatch will call the main checkout's API on :3000, not :${RAILS_API_PORT}; run: bash ~/.claude/skills/git-worktree-setup-custom/scripts/worktree-setup.sh"
      fi
    fi
    if [[ -n "${stack_problem}" ]]; then
      echo "WARNING: this worktree is using the main checkout's Docker stack (${stack_problem}); run: bash ~/.claude/skills/git-worktree-setup-custom/scripts/worktree-setup.sh"
    fi
    ;;

  --unset)
    echo "unset ${MANAGED_KEYS[*]}"
    ;;

  --keys)
    printf '%s\n' "${MANAGED_KEYS[@]}"
    ;;

  --export)
    cat <<EOF
export COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME}"
export PORT_OFFSET="${PORT_OFFSET}"
export RAILS_API_PORT="${RAILS_API_PORT}"
export DISPATCH_PORT="${DISPATCH_PORT}"
export RAILS_DB_PORT="${RAILS_DB_PORT}"
export RAILS_DB_REPLICA_PORT="${RAILS_DB_REPLICA_PORT}"
export RAILS_REDIS_PORT="${RAILS_REDIS_PORT}"
export REDPANDA_KAFKA_PORT="${REDPANDA_KAFKA_PORT}"
export REDPANDA_ADMIN_PORT="${REDPANDA_ADMIN_PORT}"
export REDPANDA_SCHEMA_PORT="${REDPANDA_SCHEMA_PORT}"
export REDPANDA_CONSOLE_PORT="${REDPANDA_CONSOLE_PORT}"
export APPS_DB_PORT="${APPS_DB_PORT}"
export LOCATIONS_DB_PORT="${LOCATIONS_DB_PORT}"
export APPS_REDIS_PORT="${APPS_REDIS_PORT}"
export ELASTIC_MQ_PORT="${ELASTIC_MQ_PORT}"
export ELASTIC_MQ_UI_PORT="${ELASTIC_MQ_UI_PORT}"
export REDPANDA_BROKER="127.0.0.1:${REDPANDA_KAFKA_PORT}"
EOF
    ;;

  --dotenv|*)
    cat <<EOF
# --- Worktree Docker Stack Isolation & Ports ---
COMPOSE_PROJECT_NAME="${COMPOSE_PROJECT_NAME}"
PORT_OFFSET="${PORT_OFFSET}"
RAILS_API_PORT="${RAILS_API_PORT}"
DISPATCH_PORT="${DISPATCH_PORT}"
RAILS_DB_PORT="${RAILS_DB_PORT}"
RAILS_DB_REPLICA_PORT="${RAILS_DB_REPLICA_PORT}"
RAILS_REDIS_PORT="${RAILS_REDIS_PORT}"
REDPANDA_KAFKA_PORT="${REDPANDA_KAFKA_PORT}"
REDPANDA_ADMIN_PORT="${REDPANDA_ADMIN_PORT}"
REDPANDA_SCHEMA_PORT="${REDPANDA_SCHEMA_PORT}"
REDPANDA_CONSOLE_PORT="${REDPANDA_CONSOLE_PORT}"
APPS_DB_PORT="${APPS_DB_PORT}"
LOCATIONS_DB_PORT="${LOCATIONS_DB_PORT}"
APPS_REDIS_PORT="${APPS_REDIS_PORT}"
ELASTIC_MQ_PORT="${ELASTIC_MQ_PORT}"
ELASTIC_MQ_UI_PORT="${ELASTIC_MQ_UI_PORT}"
REDPANDA_BROKER="127.0.0.1:${REDPANDA_KAFKA_PORT}"
EOF
    ;;
esac
