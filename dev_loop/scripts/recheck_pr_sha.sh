#!/bin/sh
# recheck_pr_sha.sh — compare the PR's current HEAD SHA against the value
# pinned at the start of this iter. Detects force-pushes between squad review
# and merge gate. Emits: sha-same | sha-drifted
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

# cd to repo top-level so cwd-relative paths (config files, lib helpers,
# .dev_loop_worktree, .tracker/runs) resolve consistently when the
# operator invoked tracker from a subdirectory. setup_run.sh publishes
# DEV_LOOP_REPO_ROOT after its own cd; downstream nodes run in fresh
# shells at tracker's original cwd, so re-anchor here.
if [ -n "${DEV_LOOP_REPO_ROOT:-}" ] && [ -d "${DEV_LOOP_REPO_ROOT}" ]; then
  cd "${DEV_LOOP_REPO_ROOT}"
fi

if [ ! -f "${RUN_DIR}/pr_head_sha.txt" ] || [ ! -f "${RUN_DIR}/pr_number.txt" ]; then
  printf 'sha-drifted'
  exit 0
fi
pinned=$(cat "${RUN_DIR}/pr_head_sha.txt")
pr_num=$(cat "${RUN_DIR}/pr_number.txt")

current=$(gh pr view "${pr_num}" --json headRefOid --jq '.headRefOid' 2>/dev/null) \
  || { printf 'sha-drifted'; exit 0; }

if [ "${pinned}" = "${current}" ]; then
  printf 'sha-same'
else
  printf '%s\n' "${current}" > "${RUN_DIR}/pr_head_sha_drift.txt"
  printf 'sha-drifted'
fi
