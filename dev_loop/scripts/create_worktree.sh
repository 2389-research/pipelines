#!/bin/sh
# create_worktree.sh — provision a git worktree for the implementer agent.
# Emits: worktree-ok | worktree-failed
#
# Layout:
#   $RUN_DIR/worktree/                    — the git worktree itself
#   $RUN_DIR/worktree.path                — absolute path to the worktree (for tracker fs-jail)
#   $RUN_DIR/worktree_error.txt           — populated only on worktree-failed
#
# Also symlinks $(pwd)/.dev_loop_worktree -> $RUN_DIR/worktree so the
# Implementer's writable_paths glob (.dev_loop_worktree/**) resolves correctly.
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then
  printf 'worktree-failed'
  exit 0
fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"
mkdir -p "${RUN_DIR}"

emit_failure() {
  printf '%s\n' "$1" > "${RUN_DIR}/worktree_error.txt" 2>/dev/null || true
  printf 'worktree-failed'
  exit 0
}

trap 'if [ $? -ne 0 ]; then printf "worktree-failed"; fi' EXIT

if [ ! -f "${RUN_DIR}/branch_name.txt" ] || [ ! -f "${RUN_DIR}/selected_issue_number.txt" ]; then
  emit_failure "missing branch_name.txt or selected_issue_number.txt"
fi

branch=$(cat "${RUN_DIR}/branch_name.txt")
issue_num=$(cat "${RUN_DIR}/selected_issue_number.txt")
worktree_path="${RUN_DIR}/worktree"
symlink="$(pwd)/.dev_loop_worktree"

# Clean any leftover from a prior failed run.
if [ -L "${symlink}" ] || [ -e "${symlink}" ]; then
  rm -rf "${symlink}"
fi
if [ -d "${worktree_path}" ]; then
  git worktree remove --force "${worktree_path}" 2>/dev/null || rm -rf "${worktree_path}"
fi

# Branch off the configured base. If branch already exists (e.g. left over from
# a previous failed iter), check it out instead of creating fresh.
if git rev-parse --verify "refs/heads/${branch}" >/dev/null 2>&1; then
  git worktree add "${worktree_path}" "${branch}" \
    > "${RUN_DIR}/worktree_error.txt" 2>&1 \
    || emit_failure "git worktree add (existing branch) failed: $(cat "${RUN_DIR}/worktree_error.txt")"
else
  git worktree add -b "${branch}" "${worktree_path}" main \
    > "${RUN_DIR}/worktree_error.txt" 2>&1 \
    || emit_failure "git worktree add (new branch) failed: $(cat "${RUN_DIR}/worktree_error.txt")"
fi

# Symlink so the Implementer's static writable_paths glob resolves.
ln -s "${worktree_path}" "${symlink}"

printf '%s' "${worktree_path}" > "${RUN_DIR}/worktree.path"
printf '%s' "${branch}" > "${RUN_DIR}/active_branch.txt"
printf 'created worktree for branch %s at %s (issue #%s)\n' \
  "${branch}" "${worktree_path}" "${issue_num}" \
  > "${RUN_DIR}/worktree_log.txt"
# Clear the error file when we succeed.
: > "${RUN_DIR}/worktree_error.txt"

printf 'worktree-ok'
