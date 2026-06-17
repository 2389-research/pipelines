#!/bin/sh
# merge_pr.sh — squash-merge the PR.
# Emits: merge-ok | merge-blocked
#
# When merge is blocked, the specific class (branch protection / merge
# conflict / missing required reviews / unknown) is written to
# $RUN_DIR/merge_block_reason.txt for ratchet_log. The router only needs to
# know "merge-blocked" so it can route to CleanupWorktree.
set -eu

# ---begin-bootstrap-reference---
STATE_ROOT_DEFAULT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop"
if [ -n "${DEV_LOOP_STATE_ROOT:-}" ]; then
  DIP_ROOT="${DEV_LOOP_STATE_ROOT}"
elif [ -r "${STATE_ROOT_DEFAULT}/.last_dip_root" ]; then
  DIP_ROOT=$(cat "${STATE_ROOT_DEFAULT}/.last_dip_root" 2>/dev/null || true)
  [ -n "${DIP_ROOT}" ] || DIP_ROOT="${STATE_ROOT_DEFAULT}"
else
  DIP_ROOT="${STATE_ROOT_DEFAULT}"
fi
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

# cd to repo top-level so cwd-relative paths (config files, lib
# helpers, .dev_loop_worktree, executor artifact root) resolve
# consistently when the operator invoked tracker from a subdirectory.
# setup_run.sh publishes DEV_LOOP_REPO_ROOT after its own cd;
# downstream nodes run in fresh shells, so re-anchor here.
if [ -n "${DEV_LOOP_REPO_ROOT:-}" ] && [ -d "${DEV_LOOP_REPO_ROOT}" ]; then
  cd "${DEV_LOOP_REPO_ROOT}"
fi

if [ ! -f "${RUN_DIR}/pr_number.txt" ]; then
  printf 'merge-blocked'
  exit 0
fi
pr_num=$(cat "${RUN_DIR}/pr_number.txt")

# Pin the HEAD SHA so gh refuses to merge if the PR head changed between
# RecheckPRSHA and this command. Closes the residual race window — LocalGates
# + PollCI run in between, and a force-push during that window would
# otherwise land here unreviewed.
match_arg=""
if [ -f "${RUN_DIR}/pr_head_sha.txt" ]; then
  pinned_sha=$(cat "${RUN_DIR}/pr_head_sha.txt")
  if [ -n "${pinned_sha}" ]; then
    match_arg="--match-head-commit=${pinned_sha}"
  fi
fi

# shellcheck disable=SC2086
merge_out=$(gh pr merge "${pr_num}" --squash --delete-branch ${match_arg} 2>&1) && rc=0 || rc=$?

if [ "${rc}" -eq 0 ]; then
  printf '%s\n' "${merge_out}" > "${RUN_DIR}/merge_log.txt"
  printf 'merge-ok'
  exit 0
fi

printf '%s\n' "${merge_out}" > "${RUN_DIR}/merge_error.txt"

# Classify the failure for the ratchet log; the routing marker stays the same.
lower=$(printf '%s' "${merge_out}" | tr '[:upper:]' '[:lower:]')
case "${lower}" in
  *"branch protection"*|*"required status check"*|*"approving review"*)
    reason='protected'
    ;;
  *"conflict"*|*"not mergeable"*|*"is not in mergeable state"*)
    reason='conflicts'
    ;;
  *"missing required reviews"*|*"review required"*)
    reason='missing-reviews'
    ;;
  *"expected head sha"*|*"head sha did not match"*|*"head commit did not match"*)
    reason='sha-drifted'
    ;;
  *)
    reason='unknown'
    ;;
esac
printf '%s' "${reason}" > "${RUN_DIR}/merge_block_reason.txt"

printf 'merge-blocked'
