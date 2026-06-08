#!/bin/sh
# setup_run.sh — initialize the per-run state directory and verify prereqs.
# Emits: setup-ok | setup-resume-required | setup-failed
#
# Runs under dash (tracker invokes via `sh -c <content>` — the shebang is
# advisory). POSIX-portable; no bash arrays, no trap ERR, no `[[ ]]`.
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

# EXIT trap as a safety net for unexpected non-zero exits.
trap 'if [ $? -ne 0 ]; then printf "setup-failed"; exit 0; fi' EXIT

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

# GH_REPO lock — downstream `gh` invocations source this env file.
{
  printf 'GH_REPO=2389-research/pipelines\n'
  printf 'DEV_LOOP_RUN_ID=%s\n' "${rid}"
  printf 'DEV_LOOP_RUN_DIR=%s\n' "${run_dir}"
} > "${run_dir}/env"

printf 'setup-ok'
