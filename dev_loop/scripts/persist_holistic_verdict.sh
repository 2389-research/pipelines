#!/bin/sh
# persist_holistic_verdict.sh — capture SquadHolistic's JSON verdict to disk.
# Emits ctx.outcome=success on persist-ok, fail on persist-failed (sh -c exit).
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then exit 1; fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"
mkdir -p "${RUN_DIR}"

# Resolve tracker's active artifact dir. Hard contract:
#   1. If the per-run env file exists, setup_run.sh ran and was responsible
#      for pinning TRACKER_RUN_DIR there. If TRACKER_RUN_DIR is then missing
#      or invalid, something corrupted the env file — falling back to ls -dt
#      mtime would defeat the concurrency-isolation guarantee and silently
#      route to whichever run finished most recently. Fail closed.
#   2. If the env file does not exist (operator invoked us before setup, or
#      this is a bats fixture without one), use the ls -dt heuristic as a
#      best-effort discovery.
TRACKER_ROOT="$(pwd)/.tracker/runs"
if [ -f "${RUN_DIR}/env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${RUN_DIR}/env"
  set +a
  if [ -z "${TRACKER_RUN_DIR:-}" ] || [ ! -d "${TRACKER_RUN_DIR}" ]; then
    tracker_run_dir=""
  else
    tracker_run_dir="${TRACKER_RUN_DIR%/}/"
  fi
else
  # shellcheck disable=SC2012
  tracker_run_dir=$(ls -dt "${TRACKER_ROOT}"/*/ 2>/dev/null | head -1)
fi
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
verdict_text=$(cat "${target}")
cat <<DATA

<verdict_holistic>
${verdict_text}
</verdict_holistic>
DATA
