#!/bin/sh
# local_gates.sh — deterministic gates on the implementer's diff before merge.
# Emits: gates-pass | gates-fail
#
# Runs (in order; first failure short-circuits and records its name):
#   1. dippin check on every *.dip touched in the diff (clean required)
#   2. (optional) the repo's local_test_command from config — currently a no-op
#
# Note: language-level (dippin check) only — no executor-level validator
# runs here (#44). The `local_test_command` key in
# `dev_loop/config/dev_loop.config.yaml` is reserved for a future hook that
# would let operators chain `tracker validate` (or another executor's
# validator) into this gate; today the loader is a no-op stub, so adding it
# to YAML has no effect. Wiring that hook is its own PR.
set -eu

# ---begin-bootstrap-reference---
STATE_ROOT_DEFAULT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop"
if [ -n "${DEV_LOOP_STATE_ROOT:-}" ]; then
  DIP_ROOT="${DEV_LOOP_STATE_ROOT}"
elif [ -f "${STATE_ROOT_DEFAULT}/.last_dip_root" ] \
     && [ ! -L "${STATE_ROOT_DEFAULT}/.last_dip_root" ] \
     && [ -r "${STATE_ROOT_DEFAULT}/.last_dip_root" ]; then
  DIP_ROOT=$(cat "${STATE_ROOT_DEFAULT}/.last_dip_root" 2>/dev/null || true)
  [ -n "${DIP_ROOT}" ] && [ -d "${DIP_ROOT}" ] || DIP_ROOT="${STATE_ROOT_DEFAULT}"
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

emit_failure() {
  printf '%s\n' "$1" > "${RUN_DIR}/gates_error.txt" 2>/dev/null || true
  printf 'gates-fail'
  exit 0
}

trap 'if [ $? -ne 0 ]; then printf "gates-fail"; exit 0; fi' EXIT

if [ ! -f "${RUN_DIR}/worktree.path" ]; then
  emit_failure "worktree.path missing"
fi
worktree_path=$(cat "${RUN_DIR}/worktree.path")
if [ ! -d "${worktree_path}" ]; then
  emit_failure "worktree path does not exist: ${worktree_path}"
fi

cd "${worktree_path}"

# Collect changed .dip files since BASE_BRANCH (sourced from env via bootstrap).
# Include renames (R) so a rename+modified .dip is still gated; without R,
# `--diff-filter=AM` would skip the renamed path entirely.
changed_dips=$(git diff --name-only --diff-filter=AMR "${BASE_BRANCH}...HEAD" -- '*.dip' 2>/dev/null || true)

: > "${RUN_DIR}/gates_log.txt"

if [ -n "${changed_dips}" ]; then
  for dip in ${changed_dips}; do
    if ! dippin check "${dip}" >> "${RUN_DIR}/gates_log.txt" 2>&1; then
      emit_failure "dippin check failed for ${dip}"
    fi
  done
fi

# A future config_local_test_command would chain here. v1 keeps it empty so
# the gate stays minimal — squad reviewers do the heavy lifting.

printf 'gates-pass'
