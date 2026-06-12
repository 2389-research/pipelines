#!/bin/sh
# persist_blocker_verdict.sh — capture SquadBlocker's JSON verdict to disk.
# Emits: persisted-blocker | persist-failed (issue #48).
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
# writes an actionable line to $RUN_DIR/persist_blocker_error.txt; the trap
# converts the non-zero exit into ctx.tool_marker=persist-failed so the .dip
# can route through CleanupWorktree + RatchetLog rather than halt mid-flight.
# Installed AFTER the bootstrap preamble: a bootstrap exit-1 (no .current_rid /
# missing env / env-is-symlink) signals state corruption so deep that emitting
# persist-failed would just defer the failure to CleanupWorktree's own
# bootstrap, which would re-trip the same error.
# shellcheck disable=SC2154  # rc is assigned inside the single-quoted trap body
trap 'rc=$?
      if [ "${rc}" -ne 0 ]; then
        [ -s "${RUN_DIR}/persist_blocker_error.txt" ] \
          || printf "unexpected non-zero exit (rc=%s)\n" "${rc}" \
             > "${RUN_DIR}/persist_blocker_error.txt" 2>/dev/null || true
        printf "persist-failed"
        exit 0
      fi' EXIT

# Resolve the dip executor's active artifact dir. setup_run.sh pins DIP_ARTIFACT_DIR
# in the env file; if it's missing or invalid, fail closed rather than falling
# back to ls -dt mtime (which would silently route to whichever run finished
# most recently, defeating concurrency isolation). The breadcrumb names the
# env-var (the actionable knob), not the executor's on-disk layout — see #61.
if [ -z "${DIP_ARTIFACT_DIR:-}" ] || [ ! -d "${DIP_ARTIFACT_DIR}" ]; then
  printf 'DIP_ARTIFACT_DIR is unset or points at missing dir; was setup_run executed?\n' \
    > "${RUN_DIR}/persist_blocker_error.txt"
  exit 1
fi
dip_artifact_dir="${DIP_ARTIFACT_DIR%/}/"

response="${dip_artifact_dir}SquadBlocker/response.md"
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
