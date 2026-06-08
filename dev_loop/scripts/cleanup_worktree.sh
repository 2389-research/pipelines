#!/bin/sh
# cleanup_worktree.sh — idempotently remove the run's worktree + symlink.
# Emits: worktree-cleaned (always — even when there's nothing to clean)
#
# Idempotent: runs from every exit path AND from each agent's fallback_target.
# Never fails the pipeline; ratchet_log records the final disposition.
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
RUN_DIR=""
if [ -n "${rid}" ]; then
  RUN_DIR="${DIP_ROOT}/runs/${rid}"
fi

symlink="$(pwd)/.dev_loop_worktree"
if [ -L "${symlink}" ] || [ -e "${symlink}" ]; then
  rm -rf "${symlink}" 2>/dev/null || true
fi

if [ -n "${RUN_DIR}" ] && [ -f "${RUN_DIR}/worktree.path" ]; then
  worktree_path=$(cat "${RUN_DIR}/worktree.path")
  if [ -d "${worktree_path}" ]; then
    git worktree remove --force "${worktree_path}" 2>/dev/null \
      || rm -rf "${worktree_path}"
  fi
  printf 'cleaned %s\n' "${worktree_path}" >> "${RUN_DIR}/cleanup_log.txt" 2>/dev/null || true
fi

# Drop the .current_rid sentinel so the next setup_run starts fresh.
rm -f "${DIP_ROOT}/.current_rid" 2>/dev/null || true

printf 'worktree-cleaned'
