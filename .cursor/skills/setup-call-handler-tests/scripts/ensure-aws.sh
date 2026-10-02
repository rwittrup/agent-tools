#!/usr/bin/env bash
# Ensure an AWS session exists; if not, attempt `aws login` (opens a browser, waits for approval).
# Exit 0 = logged in; 2 = needs the user (login failed or timed out). Idempotent.
# Env: AWS_LOGIN_TIMEOUT seconds to wait for the browser flow (default 180).
set -uo pipefail

logged_in() { aws sts get-caller-identity >/dev/null 2>&1; }

command -v aws >/dev/null 2>&1 || { echo "FAILED: aws CLI not installed"; exit 1; }

if logged_in; then echo "aws: logged in"; exit 0; fi

echo "aws: session expired, running 'aws login' (approve in the browser)" >&2
aws login >&2 &
pid=$!
waited=0
while kill -0 "$pid" 2>/dev/null; do
  if ((waited >= ${AWS_LOGIN_TIMEOUT:-180})); then kill "$pid" 2>/dev/null; break; fi
  sleep 2; waited=$((waited + 2))
done
wait "$pid" 2>/dev/null

if logged_in; then echo "aws: logged in"; exit 0; fi
echo "NEEDS USER: 'aws login' did not complete. Ask the user to run: ! aws login"; exit 2
