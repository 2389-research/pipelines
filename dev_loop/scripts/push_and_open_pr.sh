#!/bin/sh
# push_and_open_pr.sh — push the implementer's branch and open (or update) the PR.
# Emits: pr-ready | pr-push-failed
#
# Outputs:
#   $RUN_DIR/pr_number.txt     — the PR number
#   $RUN_DIR/pr_url.txt        — gh's HTML URL for the PR
#   $RUN_DIR/pr_head_sha.txt   — branch HEAD SHA at the moment of the push
#   $RUN_DIR/push_error.txt    — populated only on pr-push-failed
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

emit_failure() {
  printf '%s\n' "$1" > "${RUN_DIR}/push_error.txt" 2>/dev/null || true
  printf 'pr-push-failed'
  exit 0
}

trap 'if [ $? -ne 0 ]; then printf "pr-push-failed"; exit 0; fi' EXIT

if [ ! -f "${RUN_DIR}/worktree.path" ]; then
  emit_failure "worktree.path missing"
fi
worktree_path=$(cat "${RUN_DIR}/worktree.path")
if [ ! -d "${worktree_path}" ]; then
  emit_failure "worktree path does not exist: ${worktree_path}"
fi

if [ ! -f "${RUN_DIR}/branch_name.txt" ] || [ ! -f "${RUN_DIR}/pr_title.txt" ]; then
  emit_failure "branch_name.txt or pr_title.txt missing"
fi
branch=$(cat "${RUN_DIR}/branch_name.txt")
pr_title=$(cat "${RUN_DIR}/pr_title.txt")

cd "${worktree_path}"

git push --force-with-lease --set-upstream origin "${branch}" \
  > "${RUN_DIR}/push_error.txt" 2>&1 \
  || emit_failure "git push failed: $(cat "${RUN_DIR}/push_error.txt")"

existing_pr=$(gh pr list --head "${branch}" --state open --json number,url \
              --jq '.[0]' 2>/dev/null || true)
if [ -z "${existing_pr}" ] || [ "${existing_pr}" = "null" ]; then
  pr_body_file="${RUN_DIR}/pr_body.txt"
  [ -f "${pr_body_file}" ] || pr_body_file=/dev/null
  gh pr create --base "${BASE_BRANCH}" --head "${branch}" \
    --title "${pr_title}" \
    --body-file "${pr_body_file}" \
    > "${RUN_DIR}/push_error.txt" 2>&1 \
    || emit_failure "gh pr create failed: $(cat "${RUN_DIR}/push_error.txt")"
fi

pr_view=$(gh pr view "${branch}" --json number,url,headRefOid 2>/dev/null) \
  || emit_failure "gh pr view failed for branch ${branch}"
printf '%s\n' "${pr_view}" | jq -r '.number'       > "${RUN_DIR}/pr_number.txt"
printf '%s\n' "${pr_view}" | jq -r '.url'          > "${RUN_DIR}/pr_url.txt"
printf '%s\n' "${pr_view}" | jq -r '.headRefOid'   > "${RUN_DIR}/pr_head_sha.txt"

: > "${RUN_DIR}/push_error.txt"
printf 'pr-ready'
