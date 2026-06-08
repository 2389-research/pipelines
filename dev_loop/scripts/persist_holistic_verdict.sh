#!/bin/sh
# persist_holistic_verdict.sh — capture SquadHolistic's JSON verdict to disk.
# Emits ctx.outcome=success on persist-ok, fail on persist-failed (sh -c exit).
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then exit 1; fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"
mkdir -p "${RUN_DIR}"

# Locate tracker's active run dir (latest mtime under <workdir>/.tracker/runs/).
TRACKER_ROOT="$(pwd)/.tracker/runs"
# shellcheck disable=SC2012

tracker_run_dir=$(ls -dt "${TRACKER_ROOT}"/*/ 2>/dev/null | head -1)
if [ -z "${tracker_run_dir}" ]; then
  printf 'no tracker run dir under %s\n' "${TRACKER_ROOT}" \
    > "${RUN_DIR}/persist_holistic_error.txt"
  exit 1
fi

response="${tracker_run_dir}SquadHolistic/response.md"
target="${RUN_DIR}/verdict_holistic.json"

if [ ! -f "${response}" ]; then
  printf 'response missing at %s\n' "${response}" \
    > "${RUN_DIR}/persist_holistic_error.txt"
  exit 1
fi

if ! jq '.' < "${response}" > "${target}.tmp" 2> "${RUN_DIR}/persist_holistic_error.txt"; then
  exit 1
fi
mv "${target}.tmp" "${target}"

printf 'persisted-holistic'
