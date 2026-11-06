#!/usr/bin/env bash

# One-time setup for a linked git worktree: its own Compose project and ports,
# .env, Rails key files, a spec-only stack and a prepared test DB, then a smoke spec.
#
# Usage: dev/scripts/worktree-setup.sh [--no-smoke]
#
# Idempotent: existing .env.local pins and key files are kept, .env is regenerated,
# and a running stack is left alone.

set -euo pipefail

# Custom copy of the repo's dev/scripts/worktree-setup.sh: uses this skill's worktree-env.sh
# (DISPATCH_PORT, Chrome-safe offsets). Run from inside the worktree.
CUSTOM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKTREE_ENV="${CUSTOM_DIR}/worktree-env.sh"
ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "${ROOT_DIR}"

SMOKE_SPEC="spec/lib/crush_blank_spec.rb"
run_smoke=1
for arg in "$@"; do
  case "${arg}" in
    --no-smoke) run_smoke=0 ;;
    *) echo "worktree-setup: unknown argument: ${arg}" >&2; exit 2 ;;
  esac
done

git_dir="$(git rev-parse --git-dir)"
git_common_dir="$(git rev-parse --git-common-dir)"
if [[ "${git_dir}" == "${git_common_dir}" ]]; then
  echo "worktree-setup: this is the main checkout; setup is only for linked worktrees." >&2
  exit 1
fi

# `just` loads the main checkout's .env from an ancestor directory and exports its
# project name and ports. Drop everything worktree-env.sh manages before resolving.
eval "$(bash "${WORKTREE_ENV}" --unset)"

echo "==> Pinning Docker stack identity in .env.local"
bash "${WORKTREE_ENV}" --pin
eval "$(bash "${WORKTREE_ENV}" --export)"

echo "==> Generating .env"
if [[ -n "${CLOUD_AGENT_INJECTED_SECRET_NAMES:-}" || "${SKIP_OP:-}" == "1" ]]; then
  bash dev/scripts/cloud-env.sh
else
  bash dev/scripts/root-env.sh
fi

# Dispatch serves on DISPATCH_PORT (3002 + PORT_OFFSET) and must call this worktree's API:
# the committed turbo/apps/dispatch/.env.local points at :3000, the main checkout's.
# loadConfig.js overlays the gitignored .env.local.local on top.
# root-env.sh appended the repo's worktree-env.sh block, which has no DISPATCH_PORT.
# Swap it for this skill's block.
managed_keys="$(bash "${WORKTREE_ENV}" --keys | paste -sd'|' -)"
env_tmp="$(mktemp)"
grep -vE "^(${managed_keys})=|^# --- Worktree Docker Stack Isolation" .env > "${env_tmp}" || true
bash "${WORKTREE_ENV}" --dotenv >> "${env_tmp}"
mv "${env_tmp}" .env

echo "==> Setting GOOGLE_CLIENT_SECRET from AWS"
bash "${CUSTOM_DIR}/inject-dev-google-secret.sh"

echo "==> Pointing Dispatch at this worktree's API (:${RAILS_API_PORT})"
dispatch_dir="${ROOT_DIR}/turbo/apps/dispatch"
cat > "${dispatch_dir}/.env.local.local" <<EOF
API_BASE_URL=http://127.0.0.1:${RAILS_API_PORT}
OAUTH_REDIRECT=http://127.0.0.1:${RAILS_API_PORT}/auth/:provider/callback
EOF
(cd "${dispatch_dir}" && CONFIG_ENV=local node scripts/loadConfig.js >/dev/null)

echo "==> Fetching Rails key files"
just api ensure-app-secrets

# Only what specs need: skips rails-migrate-db (seed publishes to Redpanda and hangs
# on an empty volume). Mirrors dc-start's docker_build, minus the full dependency chain.
echo "==> Starting spec stack"
if ! docker compose top rails-api 2>/dev/null | grep -q "TIME"; then
  just _build_deps
  build=--build
  [[ "${DOCKER_NO_BUILD:-}" == "1" ]] && build=
  docker compose up -d --wait rails-db rails-db-replica rails-redis
  # No --wait: the rails-api healthcheck needs services this stack skips.
  docker compose up -d ${build} --no-deps rails-api
fi

echo "==> Preparing test database"
just api reset-spec-db single

status=0
if [[ "${run_smoke}" -eq 1 ]]; then
  echo "==> Smoke spec: ${SMOKE_SPEC}"
  if just api rspec "${SMOKE_SPEC}"; then
    echo "SMOKE: PASS"
  else
    echo "SMOKE: FAIL" >&2
    status=1
  fi
fi

bash "${WORKTREE_ENV}" --status
exit "${status}"
