#!/bin/sh
# test_persist_neutral_breadcrumb.sh — static guard against executor-specific
# path strings leaking back into persist_*.sh error breadcrumbs (#61).
#
# Per-script bats coverage only exercises 2 of 8 persist scripts directly
# (test_persist_plan.bats + test_persist_verdict.bats). The other 6 ride on
# transitive coverage. This static guard catches a copy-paste regression on
# any of the 8 scripts without growing the bats matrix.
#
# Run from the repo root: ./dev_loop/tests/test_persist_neutral_breadcrumb.sh
set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="${DIR}/scripts"

if [ ! -d "${SCRIPTS_DIR}" ]; then
  echo "missing dev_loop/scripts/" >&2
  exit 2
fi

# Resolve the persist_*.sh glob explicitly into positional params BEFORE
# calling grep. If the glob ever stops matching (files renamed/moved/relocated
# under a new naming scheme), `grep ... || true` would otherwise swallow the
# "No such file or directory" error and the guard would silently exit 0 —
# weakening the regression lock. Fail loud instead.
set -- "${SCRIPTS_DIR}"/persist_*.sh
if [ "$#" -eq 0 ] || [ ! -e "$1" ]; then
  printf 'FAIL: no persist_*.sh files under %s (guard cannot run)\n' \
    "${SCRIPTS_DIR}" >&2
  exit 2
fi

# The forbidden literal: any reference to the dip executor's on-disk layout
# in a persist script's user-facing surface (comments OR printfs). The
# executor-discovery block lives in setup_run.sh; persist scripts must stay
# executor-neutral and name only ${DIP_ARTIFACT_DIR} in their breadcrumbs.
#
# We need to distinguish grep's three exit codes here:
#   0 → match(es) found     → forbidden literal present, FAIL (lock tripped)
#   1 → no matches          → guard clean, OK
#   2 → grep error          → cannot trust the result, FAIL (don't silently
#                             pass on permission/IO errors)
# A bare `grep ... || true` would collapse 1 and 2 into the same "empty hits,
# print OK" branch — a false-positive for a regression lock.
set +e
hits=$(grep -nH "tracker/runs" "$@")
grep_rc=$?
set -e

if [ "${grep_rc}" -eq 0 ]; then
  printf 'FAIL: persist_*.sh must not reference executor-specific path strings (see #61):\n%s\n' \
    "${hits}" >&2
  exit 1
elif [ "${grep_rc}" -ne 1 ]; then
  printf 'FAIL: grep exited %d while scanning persist_*.sh (guard cannot run)\n' \
    "${grep_rc}" >&2
  exit 2
fi

printf 'OK: persist_*.sh free of executor-specific path strings\n'
exit 0
