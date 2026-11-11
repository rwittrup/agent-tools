#!/usr/bin/env bash
# Run a validation kit's validate.sh and check that its report can be trusted.
#
# Usage: kit-run.sh KIT_DIR [ARGS...]      (KIT_* env such as KIT_AUDIO_DEMO=1 passes through)
# Exit:  0 every step passed and the report is consistent
#        1 a step failed (or validate.sh exited non-zero)
#        6 lint: a script would drop earlier results (see below), or has a syntax error; nothing ran
#        7 the report disagrees with itself: a FAIL could be hidden behind exit 0
#
# Why: lib/expect.sh keeps the results table and the failure count in shell arrays and resets them
# every time it is sourced, and every workflow sources it through _common.sh. A validate.sh that sources
# a workflow after its first expect_ call silently drops the earlier rows, and an earlier FAIL then exits 0.
# PASS and FAIL lines are printed as they happen and survive that reset, so counting them is an
# independent check: lines must equal table rows, and any FAIL line must mean a non-zero exit.
#
# The full output is kept in KIT_LOG_DIR (default: $TMPDIR/kit-run); only the failures, the table and the
# verdict are printed.

set -uo pipefail

usage() { echo "usage: kit-run.sh KIT_DIR [ARGS...]" >&2; exit 2; }
kit="${1:-}"
[[ -n "${kit}" && -x "${kit}/validate.sh" ]] || usage
shift
kit="$(cd "${kit}" && pwd)"
name="$(basename "${kit}")"
log_dir="${KIT_LOG_DIR:-${TMPDIR:-/tmp}/kit-run}"
mkdir -p "${log_dir}"

# --- lint: syntax, and no workflow/lib sourced after the first expect_/pass/fail call
lint_bad=0
for f in "${kit}"/*.sh; do
  bash -n "${f}" || { echo "KIT-RUN lint: syntax error in ${f}" >&2; lint_bad=1; }
  awk -v f="${f}" '
    /^[[:space:]]*#/ { next }
    !seen && /^[[:space:]]*(expect_[a-z_]+|pass|fail)[[:space:]]/ { seen = 1; next }
    seen && /(source|[[:space:]]\.)[[:space:]][^#]*(workflows\/|_common\.sh|lib\/expect\.sh)/ {
      printf "KIT-RUN lint: %s:%d sources a workflow after the first expect_ call, which resets the results table: %s\n", f, NR, $0
      bad = 1
    }
    END { exit bad }' "${f}" >&2 || lint_bad=1
done
if [[ "${lint_bad}" -ne 0 ]]; then
  echo "KIT-RUN: lint failed; move every 'source .../workflows/...' to the top of the script, before any expect_ call." >&2
  exit 6
fi

# --- run
stamp="$(date +%H%M%S)"
out="${log_dir}/${name}-${stamp}.out"
err="${log_dir}/${name}-${stamp}.err"
"${kit}/validate.sh" "$@" > "${out}" 2> "${err}"
code=$?

passes="$(grep -c '^PASS' "${err}" || true)"
fails="$(grep -c '^FAIL' "${err}" || true)"
rows="$(grep -cE '^\| .* \| (PASS|FAIL) \|' "${out}" || true)"

grep '^FAIL' "${err}" >&2 || true
grep -E '^\|' "${out}" || true

problems=""
[[ $(( passes + fails )) -eq "${rows}" ]] || problems="${problems} table has ${rows} rows but ${passes} PASS + ${fails} FAIL lines were printed;"
[[ "${fails}" -eq 0 || "${code}" -ne 0 ]] || problems="${problems} ${fails} FAIL line(s) but validate.sh exited 0;"
# A run that exits 0 without ever printing a table proves nothing. One that died early (a preflight failure)
# is a plain failure: show why.
[[ "${rows}" -gt 0 || "${code}" -ne 0 ]] || problems="${problems} validate.sh exited 0 but printed no results table;"
if [[ "${rows}" -eq 0 && "${code}" -ne 0 ]]; then
  echo "KIT-RUN: validate.sh stopped before reporting any step. Last lines:" >&2
  tail -n 8 "${err}" | cut -c1-200 >&2
fi

echo "KIT-RUN ${name}: exit=${code} pass=${passes} fail=${fails} rows=${rows} log=${out}" >&2
if [[ -n "${problems}" ]]; then
  echo "KIT-RUN: INCONSISTENT REPORT,${problems} do not trust this run." >&2
  exit 7
fi
if [[ "${code}" -ne 0 || "${fails}" -ne 0 ]]; then
  echo "KIT-RUN: FAIL" >&2
  exit 1
fi
echo "KIT-RUN: OK ${passes} step(s) passed" >&2
exit 0
