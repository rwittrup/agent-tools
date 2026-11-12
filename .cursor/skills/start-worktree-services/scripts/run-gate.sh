#!/usr/bin/env bash
# Run one gate command, keep its output in a log, and exit with the command's own status.
#
# Usage: run-gate.sh NAME [--retry-on REGEX] [--retries N] -- COMMAND [ARGS...]
#
# Why: a background task reports the exit status of the shell line, so `cmd > log; echo exit=$?`
# reads as success (exit 0) when cmd failed. This script's status IS the command's status, and
# the last line it prints names the log: `GATE NAME: exit=N attempts=K log=PATH`.
#
# A failure that is "port is already allocated" is repaired, not just retried: compose-ports.sh moves that host
# port to a free one (see git-worktree-setup-custom) and the command reruns, up to 3 times.
#
# --retry-on REGEX  rerun (default 2 more times, 5s apart) when the failed attempt's output matches
#                   REGEX. Use only for a failure known to be transient and harmless to repeat.
#
# GATE_LOG_DIR picks the log directory (default: a per-worktree dir under $TMPDIR).

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_lib.sh"

usage() { say "usage: run-gate.sh NAME [--retry-on REGEX] [--retries N] -- COMMAND [ARGS...]"; exit 2; }

name="${1:-}"
[[ -n "${name}" && "${name}" != --* ]] || usage
shift
retry_on=""; retries=2
while [[ $# -gt 0 ]]; do
  case "$1" in
    --retry-on) retry_on="${2:-}"; shift 2 ;;
    --retries) retries="${2:-}"; shift 2 ;;
    --) shift; break ;;
    *) usage ;;
  esac
done
[[ $# -gt 0 ]] || usage

log="${LOG_DIR}/${name}.log"
: > "${log}"
attempt=0; repairs=0
while :; do
  attempt=$(( attempt + 1 ))
  out="$(mktemp)"
  printf '===== attempt %s: %s\n' "${attempt}" "$*" >> "${log}"
  "$@" > "${out}" 2>&1
  code=$?
  cat "${out}" >> "${log}"
  # A bind conflict is repairable: move that one host port (compose-ports.sh) and rerun, at most 3 times per gate.
  if [[ ${code} -ne 0 && ${repairs} -lt 3 ]]; then
    conflict="$(conflict_port "${out}")"
    if [[ -n "${conflict}" ]] && repair_port_conflict "${conflict}" >&2; then
      repairs=$(( repairs + 1 ))
      say "GATE ${name}: host port ${conflict} was taken; moved it and retrying (repair ${repairs}/3)"
      printf '===== repaired port %s\n' "${conflict}" >> "${log}"
      rm -f "${out}"; sleep 2; continue
    fi
  fi
  if [[ ${code} -ne 0 && -n "${retry_on}" && ${attempt} -le ${retries} ]] && grep -Eq "${retry_on}" "${out}"; then
    say "GATE ${name}: attempt ${attempt} failed with a transient error matching '${retry_on}'; retrying"
    rm -f "${out}"; sleep 5; continue
  fi
  break
done

echo "${code}" > "${LOG_DIR}/${name}.exit"
if [[ ${code} -ne 0 ]]; then
  say "--- last lines of ${name}:"
  tail -n 15 "${out}" | cut -c1-200 >&2
  explain_port_conflict "${out}"
fi
rm -f "${out}"
say "GATE ${name}: exit=${code} attempts=${attempt} log=${log}"
exit "${code}"
