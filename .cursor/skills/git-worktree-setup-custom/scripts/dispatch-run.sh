#!/usr/bin/env bash

# Run Dispatch (Vite) for the current worktree on its own DISPATCH_PORT, calling this
# worktree's API. Stands in for `just dispatch run local`, whose package.json scripts
# hard-code --port=3002. Run from inside the worktree, after worktree-setup.sh.
#
# --strictPort: fail if the port is taken instead of Vite hopping to another one, which
# would leave you on a port you did not expect.

set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "${ROOT_DIR}"

DISPATCH_PORT="$(grep -E '^DISPATCH_PORT=' .env 2>/dev/null | tail -n 1 | cut -d= -f2- | tr -d '"' || true)"
if [[ -z "${DISPATCH_PORT}" ]]; then
  echo "dispatch-run: no DISPATCH_PORT in ${ROOT_DIR}/.env; run worktree-setup.sh first" >&2
  exit 1
fi

cd turbo/apps/dispatch
if [[ ! -f .env.local.local ]]; then
  echo "dispatch-run: .env.local.local missing, Dispatch would call the main checkout's API; run worktree-setup.sh first" >&2
  exit 1
fi

pnpm install --frozen-lockfile
CONFIG_ENV=local node scripts/loadConfig.js
echo "Dispatch UI: http://localhost:${DISPATCH_PORT}"
NODE_ENV=development exec pnpm exec vite --clearScreen=false --host=0.0.0.0 --port="${DISPATCH_PORT}" --strictPort --force
