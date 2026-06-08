#!/bin/sh
# persist_blocker_verdict.sh — capture SquadBlocker's JSON verdict to disk.
# Emits ctx.outcome=success on persist-ok, fail on persist-failed (sh -c exit).
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then exit 1; fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"
mkdir -p "${RUN_DIR}"

# Prefer the TRACKER_RUN_DIR pinned by setup_run.sh (per-pipeline-invocation
# isolation). Fall back to the latest-mtime heuristic only when the env file
# is missing — that path is unsafe under concurrent runs in the same workdir.
# shellcheck disable=SC1091
if [ -f "${RUN_DIR}/env" ]; then
  set -a; . "${RUN_DIR}/env"; set +a
fi
TRACKER_ROOT="$(pwd)/.tracker/runs"
if [ -n "${TRACKER_RUN_DIR:-}" ] && [ -d "${TRACKER_RUN_DIR}" ]; then
  tracker_run_dir="${TRACKER_RUN_DIR%/}/"
else
  # shellcheck disable=SC2012

tracker_run_dir=$(ls -dt "${TRACKER_ROOT}"/*/ 2>/dev/null | head -1)
fi
if [ -z "${tracker_run_dir}" ]; then
  printf 'no tracker run dir under %s\n' "${TRACKER_ROOT}" \
    > "${RUN_DIR}/persist_blocker_error.txt"
  exit 1
fi

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
