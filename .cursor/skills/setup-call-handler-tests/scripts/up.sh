#!/usr/bin/env bash
# Idempotent laptop bring-up for call-handler text sims: Docker, AWS, Rails, call-handler.
# Rails is started only if not healthy. call-handler is ALWAYS restarted so it
# rebuilds from the working tree (set KEEP_CALL_HANDLER=1 to leave a running one).
# Exit 2 = needs the user (AWS login failed, or 1Password approval). Logs: $LOG_DIR (default $TMPDIR/call-handler-tests).
set -uo pipefail
cd "$(git rev-parse --show-toplevel)"
LOG_DIR="${LOG_DIR:-${TMPDIR:-/tmp}/call-handler-tests}"
mkdir -p "$LOG_DIR"

rails_ok() { curl -sf -m 2 http://127.0.0.1:3000/healthz >/dev/null 2>&1 && nc -z 127.0.0.1 19092 2>/dev/null; }
ch_ok() { curl -sf -m 2 http://127.0.0.1:7002/healthz >/dev/null 2>&1; }

# wait_for <description> <timeout_s> <pid-to-watch> <check-fn> <logfile>
wait_for() {
  local what=$1 timeout=$2 pid=$3 check=$4 log=$5 waited=0
  until $check; do
    if ! kill -0 "$pid" 2>/dev/null; then
      if grep -q 'Failed to load secrets from 1Password\|not signed in to 1Password' "$log"; then
        echo "NEEDS USER: 1Password approval timed out. Ask the user to approve the prompt (or run: ! op signin), then rerun."; exit 2
      fi
      echo "FAILED: $what exited early. Last log lines ($log):"; tail -15 "$log"; exit 1
    fi
    waited=$((waited + 5))
    if ((waited > timeout)); then echo "FAILED: $what not ready after ${timeout}s ($log)"; exit 1; fi
    sleep 5
  done
  echo "ready: $what"
}

if ! docker info >/dev/null 2>&1; then
  echo "starting OrbStack"; orb start >/dev/null 2>&1
  for _ in $(seq 1 24); do docker info >/dev/null 2>&1 && break; sleep 5; done
  docker info >/dev/null 2>&1 || { echo "FAILED: Docker not available"; exit 1; }
fi

"$(dirname "$0")/ensure-aws.sh" || exit $?

if rails_ok; then
  echo "rails already up"
else
  # May prompt the user for 1Password out-of-band; that is expected.
  nohup just api run >"$LOG_DIR/api-run.log" 2>&1 &
  wait_for "rails + redpanda" 1500 $! rails_ok "$LOG_DIR/api-run.log"
fi

if [[ "${KEEP_CALL_HANDLER:-}" != 1 ]]; then
  pkill -f 'bin/call-handler-api' 2>/dev/null; sleep 1
fi
if ch_ok; then
  echo "call-handler already up (KEEP_CALL_HANDLER=1)"
else
  nohup just call-handler run >"$LOG_DIR/call-handler.log" 2>&1 &
  wait_for "call-handler" 600 $! ch_ok "$LOG_DIR/call-handler.log"
fi
echo "logs: $LOG_DIR"
