#!/usr/bin/env bash
# Start Dispatch for this worktree in the background and wait until it serves this worktree's API.
#
# Usage: dispatch-up.sh
# Exit:  0 up | 1 failed or timed out | 5 the port is held by another process
#
# Idempotent: if the Dispatch on DISPATCH_PORT already points at this worktree's API, it does nothing.
# It never kills a process it did not start; a foreign listener is reported with its owner (exit 5).
# The pid and log are in GATE_LOG_DIR (dispatch.pid, dispatch.log). Stop it with `kill $(cat dispatch.pid)`.
# Codegen and install run first and take a minute or two.

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

worktree_env
[[ -f .env ]] || { say "DISPATCH: no .env; run worktree-setup.sh first"; exit 1; }
port="$(grep -E '^DISPATCH_PORT=' .env | tail -n 1 | cut -d= -f2- | tr -d '"')"
if [[ -z "${port}" ]]; then
  say "DISPATCH: no DISPATCH_PORT in .env (a \`just\` recipe rewrote it). Run restore-env.sh, then rerun."
  exit 1
fi
want="http://127.0.0.1:${RAILS_API_PORT}"
url="http://localhost:${port}"

serves_this_worktree() {
  curl -s "${url}/config/appConfig.json" 2>/dev/null | grep -q "\"API_BASE_URL\": *\"${want}\""
}

if serves_this_worktree; then
  say "DISPATCH: already up at ${url} (API ${want})"
  exit 0
fi

if lsof -nP -iTCP:"${port}" -sTCP:LISTEN >/dev/null 2>&1; then
  say "DISPATCH: port ${port} is held by a process that is not serving this worktree's API:"
  lsof -nP -iTCP:"${port}" -sTCP:LISTEN >&2
  say "Stop it only if you started it (kill by pid). Otherwise ask the user."
  exit 5
fi

log="${LOG_DIR}/dispatch.log"
nohup bash "${SETUP_DIR}/dispatch-run.sh" > "${log}" 2>&1 < /dev/null &
pid=$!
disown "${pid}" 2>/dev/null || true
echo "${pid}" > "${LOG_DIR}/dispatch.pid"

end=$(( $(date +%s) + 420 ))
while :; do
  if ! kill -0 "${pid}" 2>/dev/null; then
    say "DISPATCH: the process exited early. Last log lines:"; tail -n 15 "${log}" | cut -c1-200 >&2; exit 1
  fi
  if [[ "$(curl -s -o /dev/null -w '%{http_code}' "${url}/" 2>/dev/null || true)" == "200" ]] && serves_this_worktree; then
    say "DISPATCH: OK ${url} (pid ${pid}, API ${want}, log ${log})"
    exit 0
  fi
  if [[ "$(date +%s)" -ge "${end}" ]]; then
    say "DISPATCH: not serving after 420s. Last log lines:"; tail -n 15 "${log}" | cut -c1-200 >&2; exit 1
  fi
  sleep 3
done
