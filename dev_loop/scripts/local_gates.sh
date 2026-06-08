#!/bin/sh
# local_gates.sh — deterministic gates on the implementer's diff before merge.
# Emits: gates-pass | gates-fail
#
# Runs (in order; first failure short-circuits and records its name):
#   1. dippin check on every *.dip touched in the diff (clean required)
#   2. tracker validate on every *.dip touched
#   3. (optional) the repo's local_test_command from config — currently a no-op
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then
  printf 'gates-fail'
  exit 0
fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"

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

# Collect changed .dip files since main.
changed_dips=$(git diff --name-only --diff-filter=AM main...HEAD -- '*.dip' 2>/dev/null || true)

: > "${RUN_DIR}/gates_log.txt"

if [ -n "${changed_dips}" ]; then
  for dip in ${changed_dips}; do
    if ! dippin check "${dip}" >> "${RUN_DIR}/gates_log.txt" 2>&1; then
      emit_failure "dippin check failed for ${dip}"
    fi
    if ! tracker validate "${dip}" >> "${RUN_DIR}/gates_log.txt" 2>&1; then
      emit_failure "tracker validate failed for ${dip}"
    fi
  done
fi

# A future config_local_test_command would chain here. v1 keeps it empty so
# the gate stays minimal — squad reviewers do the heavy lifting.

printf 'gates-pass'
