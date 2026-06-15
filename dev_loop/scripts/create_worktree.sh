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

# cd to repo top-level so cwd-relative paths (config files, lib
# helpers, .dev_loop_worktree, executor artifact root) resolve
# consistently when the operator invoked tracker from a subdirectory.
# setup_run.sh publishes DEV_LOOP_REPO_ROOT after its own cd;
# downstream nodes run in fresh shells, so re-anchor here.
if [ -n "${DEV_LOOP_REPO_ROOT:-}" ] && [ -d "${DEV_LOOP_REPO_ROOT}" ]; then
  cd "${DEV_LOOP_REPO_ROOT}"
fi

emit_failure() {
  printf '%s\n' "$1" > "${RUN_DIR}/worktree_error.txt" 2>/dev/null || true
  printf 'worktree-failed'
  exit 0
}

trap 'if [ $? -ne 0 ]; then printf "worktree-failed"; exit 0; fi' EXIT

if [ ! -f "${RUN_DIR}/branch_name.txt" ] || [ ! -f "${RUN_DIR}/selected_issue_number.txt" ]; then
  emit_failure "missing branch_name.txt or selected_issue_number.txt"
fi

branch=$(cat "${RUN_DIR}/branch_name.txt")
issue_num=$(cat "${RUN_DIR}/selected_issue_number.txt")
worktree_path="${RUN_DIR}/worktree"
symlink="$(pwd)/.dev_loop_worktree"

# Clean any leftover from a prior failed run, but ONLY if it is a symlink
# (which is what create_worktree.sh itself writes). If a user happens to have
# a real directory at .dev_loop_worktree/ we refuse to clobber it.
if [ -L "${symlink}" ]; then
  rm -f "${symlink}"
elif [ -e "${symlink}" ]; then
  emit_failure ".dev_loop_worktree exists and is not a symlink; refusing to overwrite"
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
  git worktree add -b "${branch}" "${worktree_path}" "${BASE_BRANCH:-main}" \
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
