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

# The forbidden literal: any reference to the dip executor's on-disk layout
# in a persist script's user-facing surface (comments OR printfs). The
# executor-discovery block lives in setup_run.sh; persist scripts must stay
# executor-neutral and name only ${DIP_ARTIFACT_DIR} in their breadcrumbs.
hits=$(grep -nH "tracker/runs" "${SCRIPTS_DIR}"/persist_*.sh || true)

if [ -n "${hits}" ]; then
  printf 'FAIL: persist_*.sh must not reference executor-specific path strings (see #61):\n%s\n' \
    "${hits}" >&2
  exit 1
fi

printf 'OK: persist_*.sh free of executor-specific path strings\n'
exit 0
