#!/usr/bin/env bash
# Bring up everything a simulated audio call needs (workflows/start-audio-demo in the UNCAD kits),
# make local recordings possible, and verify.
#
# Usage: audio-up.sh [--rebuild] [--no-restore]
# Exit:  0 ready | 1 a service is not running, or /audio could not be made writable
#
# Idempotent. When every audio service is already running it skips `just dc-start`, which skips the
# `.env` rewrite and the image rebuild; pass --rebuild after changing audio code. Rerun it before a
# kit run that waits for a recording: recreating audio-recorder resets /audio.
#
# --no-restore  skip restore-env.sh (services-up.sh restores once, after all of its `just` commands).

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

# The set that produced LIVE, ENDED and RECORDED states on a laptop (RSP-288). Not pruned.
AUDIO_SERVICES="apps-redis audio-demo-server audio-server audio-transcriber audio-recorder livekit-consumer rails-audio-results-consumer call-transcription-storage-consumer call-transcription-query"

rebuild=0; restore=1
for arg in "$@"; do
  case "${arg}" in
    --rebuild) rebuild=1 ;;
    --no-restore) restore=0 ;;
    *) say "usage: audio-up.sh [--rebuild] [--no-restore]"; exit 2 ;;
  esac
done

worktree_env
n_audio="$(wc -w <<<"${AUDIO_SERVICES}" | tr -d ' ')"

# shellcheck disable=SC2086
missing="$(missing_services ${AUDIO_SERVICES})"
if [[ -n "${missing}" || "${rebuild}" -eq 1 ]]; then
  # The observability sidecar (grafana) is flaky: its Pyroscope crash-loops and blocks `dc-start`
  # with "container ... is unhealthy". A rerun clears it; nothing else is retried.
  # shellcheck disable=SC2086
  bash "${SWS_DIR}/run-gate.sh" audio-start --retry-on 'container [^ ]*(grafana|otelcol)[^ ]* is unhealthy' -- \
    just dc-start ${AUDIO_SERVICES} || exit 1
  [[ "${restore}" -eq 1 ]] && { bash "${SETUP_DIR}/restore-env.sh" || exit $?; }
else
  say "AUDIO: all ${n_audio} audio services already running; skipping dc-start"
fi

# The image runs as nonroot with cwd / and mounts nothing, so audio-recorder cannot create /audio and
# every recording fails with "no such file or directory" (the call ends but never reaches RECORDED).
# Fixed in the running container only: recreating it resets this, hence the rerun advice above.
if ! docker compose exec -T audio-recorder sh -c 'test -w /audio' 2>/dev/null; then
  docker compose exec -T -u root audio-recorder sh -c 'mkdir -p /audio && chown 65532:65532 /audio' >/dev/null 2>&1
fi
if ! docker compose exec -T audio-recorder sh -c 'test -w /audio' 2>/dev/null; then
  say "AUDIO: /audio is not writable in audio-recorder, so calls will end without a recording."
  exit 1
fi

# shellcheck disable=SC2086
missing="$(missing_services ${AUDIO_SERVICES})"
if [[ -n "${missing}" ]]; then
  say "AUDIO: not running: $(printf '%s' "${missing}" | tr '\n' ' ')"
  exit 1
fi
say "AUDIO: OK (${n_audio} services running; /audio writable in audio-recorder)"
