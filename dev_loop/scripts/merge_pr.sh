#!/bin/sh
# merge_pr.sh — squash-merge the PR.
# Emits: merge-ok | merge-blocked
#
# When merge is blocked, the specific class (branch protection / merge
# conflict / missing required reviews / unknown) is written to
# $RUN_DIR/merge_block_reason.txt for ratchet_log. The router only needs to
# know "merge-blocked" so it can route to CleanupWorktree.
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then
  printf 'merge-blocked'
  exit 0
fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"

# shellcheck disable=SC1091
if [ -f "${RUN_DIR}/env" ]; then
  set -a; . "${RUN_DIR}/env"; set +a
fi
export GH_REPO="${GH_REPO:-2389-research/pipelines}"

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
