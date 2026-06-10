#!/bin/sh
# persist_testability_verdict.sh — capture SquadTestability's JSON verdict to disk.
# Emits: persisted-testability | persist-failed (issue #48).
set -eu

# ---begin-bootstrap-reference---
STATE_ROOT_DEFAULT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop"
DIP_ROOT="${DEV_LOOP_STATE_ROOT:-${STATE_ROOT_DEFAULT}}"
if [ -n "${DEV_LOOP_RUN_DIR:-}" ]; then
  RUN_DIR="${DEV_LOOP_RUN_DIR}"
else
  rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
  [ -n "${rid}" ] || { printf 'no .current_rid; was setup_run executed?\n' >&2; exit 1; }
  RUN_DIR="${DIP_ROOT}/runs/${rid}"
fi
[ -f "${RUN_DIR}/env" ] || { printf 'missing env at %s\n' "${RUN_DIR}/env" >&2; exit 1; }
[ ! -L "${RUN_DIR}/env" ] || { printf 'env is a symlink; refusing\n' >&2; exit 1; }
set -a
# shellcheck disable=SC1091
. "${RUN_DIR}/env"
set +a
# ---end-bootstrap-reference---

# Post-bootstrap failure trap (issue #48). Every exit-1 site below already
# writes an actionable line to $RUN_DIR/persist_testability_error.txt; the trap
# converts the non-zero exit into ctx.tool_marker=persist-failed so the .dip
# can route through CleanupWorktree + RatchetLog rather than halt mid-flight.
# Installed AFTER the bootstrap preamble: a bootstrap exit-1 (no .current_rid /
# missing env / env-is-symlink) signals state corruption so deep that emitting
# persist-failed would just defer the failure to CleanupWorktree's own
# bootstrap, which would re-trip the same error.
# shellcheck disable=SC2154  # rc is assigned inside the single-quoted trap body
trap 'rc=$?
      if [ "${rc}" -ne 0 ]; then
        [ -s "${RUN_DIR}/persist_testability_error.txt" ] \
          || printf "unexpected non-zero exit (rc=%s)\n" "${rc}" \
             > "${RUN_DIR}/persist_testability_error.txt" 2>/dev/null || true
        printf "persist-failed"
        exit 0
      fi' EXIT

# Resolve tracker's active artifact dir. setup_run.sh pins TRACKER_RUN_DIR in
# the env file; if it's missing or invalid, fail closed rather than falling
# back to ls -dt mtime (which would silently route to whichever run finished
# most recently, defeating concurrency isolation).
TRACKER_ROOT="$(pwd)/.tracker/runs"
if [ -z "${TRACKER_RUN_DIR:-}" ] || [ ! -d "${TRACKER_RUN_DIR}" ]; then
  printf 'no tracker run dir under %s\n' "${TRACKER_ROOT}" \
    > "${RUN_DIR}/persist_testability_error.txt"
  exit 1
fi
tracker_run_dir="${TRACKER_RUN_DIR%/}/"

response="${tracker_run_dir}SquadTestability/response.md"
target="${RUN_DIR}/verdict_testability.json"

if [ ! -f "${response}" ]; then
  printf 'response missing at %s\n' "${response}" \
    > "${RUN_DIR}/persist_testability_error.txt"
  exit 1
fi

if ! jq '.' < "${response}" > "${target}.tmp" 2> "${RUN_DIR}/persist_testability_error.txt"; then
  exit 1
fi
mv "${target}.tmp" "${target}"

printf 'persisted-testability'
verdict_text=$(cat "${target}")
cat <<DATA

<verdict_testability>
${verdict_text}
</verdict_testability>
DATA
