#!/usr/bin/env bash

# Re-apply what this skill layers on top of a regenerated .env: the worktree block (with
# DISPATCH_PORT), the AWS-sourced GOOGLE_CLIENT_SECRET, Dispatch's API, websocket and call-handler URLs, and the
# host-port override (compose-ports.sh).
#
# Usage: restore-env.sh [--allow-1password]
# Exit:  0 restored | 1 no .env, or not a linked worktree | 4 Google secret not read from AWS
#
# Why: `just dc-start`, `just api reset-db` and any other recipe that depends on `_root-env`
# regenerate .env from 1Password, which drops DISPATCH_PORT and the AWS secret. Run this after
# every such command. Only .env and Dispatch's .env.local.local change: no Docker, no 1Password.
# A container created before this ran keeps the old secret; services-up.sh checks for that.
#
# Without --allow-1password, a secret that could not be read from AWS is an error (exit 4):
# the 1Password value is rejected by Google (invalid_client). worktree-setup.sh passes the flag
# to keep its older warn-and-continue behavior.
#
# Idempotent. Run from inside the worktree.

set -euo pipefail

CUSTOM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_ENV="${CUSTOM_DIR}/worktree-env.sh"

allow_1password=0
for arg in "$@"; do
  case "${arg}" in
    --allow-1password) allow_1password=1 ;;
    *) echo "restore-env: unknown argument: ${arg}" >&2; exit 2 ;;
  esac
done

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "${ROOT_DIR}"

if [[ "$(git rev-parse --git-dir)" == "$(git rev-parse --git-common-dir)" ]]; then
  echo "restore-env: this is the main checkout; it is only for linked worktrees." >&2
  exit 1
fi
if [[ ! -f .env ]]; then
  echo "restore-env: no ${ROOT_DIR}/.env; run worktree-setup.sh first." >&2
  exit 1
fi

# `just` exports the main checkout's project name and ports; resolve this worktree's own.
eval "$(bash "${WORKTREE_ENV}" --unset)"
eval "$(bash "${WORKTREE_ENV}" --export)"

# root-env.sh appends the repo's worktree-env.sh block, which has no DISPATCH_PORT. Swap in this skill's block.
managed_keys="$(bash "${WORKTREE_ENV}" --keys | paste -sd'|' -)"
env_tmp="$(mktemp)"
grep -vE "^(${managed_keys})=|^# --- Worktree Docker Stack Isolation" .env > "${env_tmp}" || true
bash "${WORKTREE_ENV}" --dotenv >> "${env_tmp}"
mv "${env_tmp}" .env

# The same profile root-env.sh uses; without it `aws` falls back to the default profile and fails silently.
export AWS_PROFILE="${AWS_PROFILE:-prepared-dev}"
inject_out="$(bash "${CUSTOM_DIR}/inject-dev-google-secret.sh" 2>&1)"
printf '%s\n' "${inject_out}" >&2

# Dispatch serves on DISPATCH_PORT and must call this worktree's API; the committed
# turbo/apps/dispatch/.env.local points at :3000, the main checkout's. loadConfig.js overlays
# the gitignored .env.local.local on top.
#
# Two more Dispatch URLs name host ports that docker-compose.yaml publishes as literals, which compose-ports.sh may
# have moved off another worktree's: the websocket (rails-ws, stock 8080) and call-handler (stock 7002).
bash "${CUSTOM_DIR}/compose-ports.sh" write --quiet || echo "restore-env: WARNING compose-ports.sh failed; using stock host ports" >&2
ws_port="$(bash "${CUSTOM_DIR}/compose-ports.sh" port rails-ws 8080 2>/dev/null || true)"
call_handler_port="$(bash "${CUSTOM_DIR}/compose-ports.sh" port call-handler 8080 2>/dev/null || true)"
dispatch_dir="${ROOT_DIR}/turbo/apps/dispatch"
{
  echo "API_BASE_URL=http://127.0.0.1:${RAILS_API_PORT}"
  echo "OAUTH_REDIRECT=http://127.0.0.1:${RAILS_API_PORT}/auth/:provider/callback"
  [[ -z "${ws_port}" ]] || echo "API_WEBSOCKET_URL=ws://127.0.0.1:${ws_port}/cable"
  [[ -z "${call_handler_port}" ]] || echo "CALL_HANDLER_URL=http://localhost:${call_handler_port}"
} > "${dispatch_dir}/.env.local.local"
(cd "${dispatch_dir}" && CONFIG_ENV=local node scripts/loadConfig.js >/dev/null)

dispatch_port="$(grep -E '^DISPATCH_PORT=' .env | tail -n 1 | cut -d= -f2- | tr -d '"')"
echo "restore-env: DISPATCH_PORT=${dispatch_port} API_BASE_URL=http://127.0.0.1:${RAILS_API_PORT}" >&2

if ! grep -q 'GOOGLE_CLIENT_SECRET set from AWS' <<<"${inject_out}"; then
  if [[ "${allow_1password}" -eq 1 ]]; then
    echo "restore-env: WARNING Google secret not read from AWS; Google login may fail with invalid_client" >&2
  else
    echo "restore-env: the Google secret was not read from AWS. Run preflight.sh (aws sso login --profile ${AWS_PROFILE}), then rerun." >&2
    exit 4
  fi
fi
