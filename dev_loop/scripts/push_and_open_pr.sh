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

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then
  printf 'pr-push-failed'
  exit 0
fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"
mkdir -p "${RUN_DIR}"

emit_failure() {
  printf '%s\n' "$1" > "${RUN_DIR}/push_error.txt" 2>/dev/null || true
  printf 'pr-push-failed'
  exit 0
}

trap 'if [ $? -ne 0 ]; then printf "pr-push-failed"; fi' EXIT

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

# shellcheck disable=SC1091
if [ -f "${RUN_DIR}/env" ]; then
  set -a; . "${RUN_DIR}/env"; set +a
fi
export GH_REPO="${GH_REPO:-2389-research/pipelines}"

cd "${worktree_path}"

git push --force-with-lease --set-upstream origin "${branch}" \
  > "${RUN_DIR}/push_error.txt" 2>&1 \
  || emit_failure "git push failed: $(cat "${RUN_DIR}/push_error.txt")"

existing_pr=$(gh pr list --head "${branch}" --state open --json number,url \
              --jq '.[0]' 2>/dev/null || true)
if [ -z "${existing_pr}" ] || [ "${existing_pr}" = "null" ]; then
  pr_body_file="${RUN_DIR}/pr_body.txt"
  [ -f "${pr_body_file}" ] || pr_body_file=/dev/null
  gh pr create --base main --head "${branch}" \
    --title "${pr_title}" \
    --body-file "${pr_body_file}" \
    > "${RUN_DIR}/push_error.txt" 2>&1 \
    || emit_failure "gh pr create failed: $(cat "${RUN_DIR}/push_error.txt")"
fi

pr_view=$(gh pr view "${branch}" --json number,url,headRefOid 2>/dev/null) \
  || emit_failure "gh pr view failed for branch ${branch}"
echo "${pr_view}" | jq -r '.number'       > "${RUN_DIR}/pr_number.txt"
echo "${pr_view}" | jq -r '.url'          > "${RUN_DIR}/pr_url.txt"
echo "${pr_view}" | jq -r '.headRefOid'   > "${RUN_DIR}/pr_head_sha.txt"

: > "${RUN_DIR}/push_error.txt"
printf 'pr-ready'
