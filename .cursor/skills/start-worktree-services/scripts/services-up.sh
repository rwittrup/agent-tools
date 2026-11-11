#!/usr/bin/env bash
# Start a linked worktree's stack for a validation kit, in the order that works, and verify it.
#
# Usage: services-up.sh [--reset] [--audio] [--dispatch] [--rebuild] [--extra "svc svc"]
#   --reset      first `just api reset-db` (drops, migrates and seeds this worktree's database)
#   --audio      also bring up the audio pipeline (audio-up.sh): needed for simulated calls
#   --dispatch   also start Dispatch (dispatch-up.sh): needed when the kit is driven in a browser
#   --rebuild    run `just dc-start` even when the services are already running (picks up code changes)
#   --extra      more compose services, for example "incident-search" for the Triage list
# Exit:  0 up and verified | non-zero names the failing step (preflight: 1-3, restore-env: 4, dispatch: 5)
#
# Order: preflight -> every `just` command -> restore-env.sh once -> verify. `just` regenerates .env from
# 1Password each time, so restoring once after the last one is enough. Services already running are left
# alone, which also skips the .env rewrite. Logs are in GATE_LOG_DIR (set it to your scratchpad).

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

API_SERVICES="rails-api rails-grpc rails-goodjob rails-ws rails-ws-rpc locations-api rbac-api"
FLAKE='container [^ ]*(grafana|otelcol)[^ ]* is unhealthy'

reset=0; audio=0; dispatch=0; rebuild=0; extra=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --reset) reset=1; shift ;;
    --audio) audio=1; shift ;;
    --dispatch) dispatch=1; shift ;;
    --rebuild) rebuild=1; shift ;;
    --extra) extra="${2:-}"; shift 2 ;;
    *) say "usage: services-up.sh [--reset] [--audio] [--dispatch] [--rebuild] [--extra \"svc svc\"]"; exit 2 ;;
  esac
done
services="${API_SERVICES} ${extra}"

bash "${SWS_DIR}/preflight.sh" || exit $?
worktree_env

if [[ "${reset}" -eq 1 ]]; then
  say "SERVICES: resetting the database (just api reset-db)"
  bash "${SWS_DIR}/run-gate.sh" reset-db --retry-on "${FLAKE}" -- just api reset-db || exit 11
fi

# shellcheck disable=SC2086
missing="$(missing_services ${services})"
if [[ -n "${missing}" || "${rebuild}" -eq 1 ]]; then
  # shellcheck disable=SC2086
  bash "${SWS_DIR}/run-gate.sh" api-start --retry-on "${FLAKE}" -- just dc-start ${services} || exit 12
else
  say "SERVICES: API services already running; skipping dc-start"
fi

if [[ "${audio}" -eq 1 ]]; then
  audio_args=(--no-restore)
  [[ "${rebuild}" -eq 1 ]] && audio_args+=(--rebuild)
  bash "${SWS_DIR}/audio-up.sh" "${audio_args[@]}" || exit 13
fi

# After the last `just` command: it rewrote .env, so put DISPATCH_PORT and the AWS Google secret back.
bash "${SETUP_DIR}/restore-env.sh" || exit $?

# A container created before the restore holds the 1Password secret, which Google rejects (invalid_client).
env_sha="$(env_secret_sha)"
ctr_sha="$(docker compose exec -T rails-api sh -c 'printf %s "$GOOGLE_CLIENT_SECRET"' 2>/dev/null | shasum -a 256 | cut -c1-12)"
if [[ "${env_sha}" != "${ctr_sha}" ]]; then
  say "SERVICES: rails-api holds a different Google secret than .env; recreating it"
  docker compose up -d --force-recreate --no-deps rails-api >/dev/null 2>&1 || exit 14
  ctr_sha="$(docker compose exec -T rails-api sh -c 'printf %s "$GOOGLE_CLIENT_SECRET"' 2>/dev/null | shasum -a 256 | cut -c1-12)"
  [[ "${env_sha}" == "${ctr_sha}" ]] || { say "SERVICES: rails-api still has the wrong Google secret (.env ${env_sha}, container ${ctr_sha})"; exit 14; }
fi

# shellcheck disable=SC2086
missing="$(missing_services ${services})"
if [[ -n "${missing}" ]]; then
  say "SERVICES: not running, starting once more: $(printf '%s' "${missing}" | tr '\n' ' ')"
  # shellcheck disable=SC2086
  docker compose up -d --no-deps ${missing} >/dev/null 2>&1
  # shellcheck disable=SC2086
  missing="$(missing_services ${services})"
  [[ -z "${missing}" ]] || { say "SERVICES: still not running: $(printf '%s' "${missing}" | tr '\n' ' ')"; exit 15; }
fi

if ! wait_http "http://localhost:${RAILS_API_PORT}/healthz" 200 120; then
  say "SERVICES: http://localhost:${RAILS_API_PORT}/healthz did not return 200"
  exit 16
fi

if [[ "${dispatch}" -eq 1 ]]; then
  bash "${SWS_DIR}/dispatch-up.sh" || exit $?
fi

say "SERVICES: OK  API http://localhost:${RAILS_API_PORT} (healthz 200, Google secret ${env_sha})"
[[ "${dispatch}" -eq 1 ]] && say "SERVICES: Dispatch http://localhost:${DISPATCH_PORT:-?}"
just worktree-info 2>/dev/null | grep -E 'Rails API|Rails Primary DB|Redpanda Kafka|Apps DB|Locations DB' >&2 || true
exit 0
