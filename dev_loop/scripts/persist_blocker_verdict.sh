#!/bin/sh
# persist_blocker_verdict.sh — capture SquadBlocker's JSON verdict to disk.
# Emits ctx.outcome=success on persist-ok, fail on persist-failed (sh -c exit).
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

# Resolve tracker's active artifact dir. setup_run.sh pins TRACKER_RUN_DIR in
# the env file; if it's missing or invalid, fail closed rather than falling
# back to ls -dt mtime (which would silently route to whichever run finished
# most recently, defeating concurrency isolation).
TRACKER_ROOT="$(pwd)/.tracker/runs"
if [ -z "${TRACKER_RUN_DIR:-}" ] || [ ! -d "${TRACKER_RUN_DIR}" ]; then
  printf 'no tracker run dir under %s\n' "${TRACKER_ROOT}" \
    > "${RUN_DIR}/persist_blocker_error.txt"
  exit 1
fi
tracker_run_dir="${TRACKER_RUN_DIR%/}/"

response="${tracker_run_dir}SquadBlocker/response.md"
target="${RUN_DIR}/verdict_blocker.json"

if [ ! -f "${response}" ]; then
  printf 'response missing at %s\n' "${response}" \
    > "${RUN_DIR}/persist_blocker_error.txt"
  exit 1
fi

if ! jq '.' < "${response}" > "${target}.tmp" 2> "${RUN_DIR}/persist_blocker_error.txt"; then
  exit 1
fi
mv "${target}.tmp" "${target}"

printf 'persisted-blocker'
verdict_text=$(cat "${target}")
cat <<DATA

<verdict_blocker>
${verdict_text}
</verdict_blocker>
DATA
