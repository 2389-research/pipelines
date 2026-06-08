#!/bin/sh
# setup_run.sh — initialize the per-run state directory and verify prereqs.
# Emits: setup-ok | setup-resume-required | setup-failed
#
# Runs under dash (tracker invokes via `sh -c <content>` — the shebang is
# advisory). POSIX `sh` style (no bash arrays, no `trap ERR`, no `[[ ]]`),
# augmented with a few Linux-only utilities where they read clearly
# (`find -mmin`, GNU stat). dev_loop already requires Linux for the
# writable_paths Landlock jail, so the Linux pin is not a new constraint.
#
# State layout:
#   $DIP_ROOT/.current_rid               — sentinel pointing at the active run
#   $DIP_ROOT/runs/<rid>/rid.txt         — the run id (idempotent record)
#   $DIP_ROOT/runs/<rid>/started_at.txt  — UTC ISO 8601 timestamp
#   $DIP_ROOT/runs/<rid>/env             — KEY=VALUE pairs downstream scripts source
#   $DIP_ROOT/runs/<rid>/setup_error.txt — populated only on setup-failed
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
mkdir -p "${DIP_ROOT}/runs"

# Resume detection: if a prior run still has a worktree, signal the operator
# to invoke `tracker --resume`. We do NOT auto-resume from setup_run — the
# upstream pipeline routes the marker straight to Exit.
if [ -f "${DIP_ROOT}/.current_rid" ]; then
  prev_rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
  if [ -n "${prev_rid}" ] && [ -d "${DIP_ROOT}/runs/${prev_rid}/worktree" ]; then
    printf 'setup-resume-required'
    exit 0
  fi
fi

rid="$(date -u +%Y%m%dT%H%M%SZ)-$$"
run_dir="${DIP_ROOT}/runs/${rid}"

emit_failure() {
  mkdir -p "${run_dir}" 2>/dev/null || true
  printf '%s\n' "$1" > "${run_dir}/setup_error.txt" 2>/dev/null || true
  printf 'setup-failed'
  exit 0
}

# EXIT trap as a safety net for unexpected non-zero exits. Records the rc
# into setup_error.txt so post-mortems can find that it tripped — the
# explicit `emit_failure` paths still produce richer per-mode messages.
#
# `LINENO` is intentionally NOT referenced here: dash does not guarantee it
# is set, and under `set -u` an unset `${LINENO}` would error inside the
# trap itself, suppressing the setup-failed marker and leaving the pipeline
# with no routable outcome. The rc alone is enough breadcrumb.
# shellcheck disable=SC2154  # rc is assigned inside the single-quoted trap body
trap 'rc=$?; if [ "${rc}" -ne 0 ]; then
        mkdir -p "${run_dir}" 2>/dev/null || true
        printf "unexpected non-zero exit (rc=%s)\n" "${rc}" \
          > "${run_dir}/setup_error.txt" 2>/dev/null || true
        printf "setup-failed"
        exit 0
      fi' EXIT

# Concurrency lock — atomic mkdir is the POSIX-portable pattern. Without
# this, a second `tracker dev_loop/dev_loop.dip` started in the same workdir
# during the early window (after setup_run but before CreateWorktree)
# overwrites .current_rid and corrupts the first run's RUN_DIR resolution.
# cleanup_worktree.sh releases the lock at pipeline exit. The lock dir's
# mtime is used as a staleness signal: anything older than 4 hours is
# considered abandoned and reclaimed (covers crashed runs that never reached
# CleanupWorktree).
LOCK_DIR="${DIP_ROOT}/.dev_loop.lock"
LOCK_STALE_MIN=240
if ! mkdir "${LOCK_DIR}" 2>/dev/null; then
  if [ -n "$(find "${LOCK_DIR}" -maxdepth 0 -mmin "+${LOCK_STALE_MIN}" 2>/dev/null)" ]; then
    rm -rf "${LOCK_DIR}" 2>/dev/null || true
    mkdir "${LOCK_DIR}"
  else
    holder=$(cat "${LOCK_DIR}/rid" 2>/dev/null || printf '<unknown>')
    mkdir -p "${run_dir}"
    {
      printf 'another dev_loop run is active (rid=%s)\n' "${holder}"
      printf 'release the lock if it is stale: rm -rf %s\n' "${LOCK_DIR}"
    } > "${run_dir}/setup_error.txt"
    printf 'setup-failed'
    exit 0
  fi
fi
printf '%s' "${rid}" > "${LOCK_DIR}/rid"

mkdir -p "${run_dir}"
printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid"
printf '%s\n' "${rid}" > "${run_dir}/rid.txt"
date -u +%Y-%m-%dT%H:%M:%SZ > "${run_dir}/started_at.txt"

# Verify prerequisite tooling.
missing=""
for cmd in gh jq git tracker; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    missing="${missing}${missing:+ }${cmd}"
  fi
done
if [ -n "${missing}" ]; then
  emit_failure "missing required commands: ${missing}"
fi

# Discover tracker's per-invocation artifact dir NOW (at pipeline start) so
# downstream persist scripts can address it explicitly rather than via
# ls -dt mtime — which would clash with any concurrent tracker run in the
# same workdir. tracker creates <workdir>/.tracker/runs/<runID>/ when it
# starts, so by the time SetupRun executes the dir already exists and is
# the newest under .tracker/runs.
TRACKER_ROOT="$(pwd)/.tracker/runs"
# shellcheck disable=SC2012
tracker_run_dir=$(ls -dt "${TRACKER_ROOT}"/*/ 2>/dev/null | head -1)
# Strip the trailing slash for cleaner env-file output.
tracker_run_dir=${tracker_run_dir%/}

# GH_REPO lock + per-run identity — downstream `gh` invocations and persist
# scripts source this env file.
{
  printf 'GH_REPO=2389-research/pipelines\n'
  printf 'DEV_LOOP_RUN_ID=%s\n' "${rid}"
  printf 'DEV_LOOP_RUN_DIR=%s\n' "${run_dir}"
  if [ -n "${tracker_run_dir}" ]; then
    printf 'TRACKER_RUN_DIR=%s\n' "${tracker_run_dir}"
  fi
} > "${run_dir}/env"

printf 'setup-ok'
