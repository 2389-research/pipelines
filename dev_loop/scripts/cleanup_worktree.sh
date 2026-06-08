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
# Only unlink when it IS the symlink we created. If a user has a real
# directory at this path we leave it alone (and let the rest of cleanup
# proceed) — never `rm -rf` an unrelated dir that happens to match the name.
if [ -L "${symlink}" ]; then
  rm -f "${symlink}" 2>/dev/null || true
elif [ -e "${symlink}" ]; then
  if [ -n "${RUN_DIR}" ]; then
    printf 'refused to clean .dev_loop_worktree (not a symlink)\n' \
      >> "${RUN_DIR}/cleanup_log.txt" 2>/dev/null || true
  fi
fi

if [ -n "${RUN_DIR}" ] && [ -f "${RUN_DIR}/worktree.path" ]; then
  worktree_path=$(cat "${RUN_DIR}/worktree.path")
  # Validate the path is inside RUN_DIR before destructive removal. A
  # corrupted worktree.path file (or a malicious override) could otherwise
  # delete arbitrary directories. create_worktree.sh always writes
  # "${RUN_DIR}/worktree", so anything else is rejected.
  expected_prefix="${RUN_DIR}/worktree"
  case "${worktree_path}" in
    "${expected_prefix}"|"${expected_prefix}"/*)
      if [ -d "${worktree_path}" ]; then
        git worktree remove --force "${worktree_path}" 2>/dev/null \
          || rm -rf "${worktree_path}"
      fi
      printf 'cleaned %s\n' "${worktree_path}" \
        >> "${RUN_DIR}/cleanup_log.txt" 2>/dev/null || true
      ;;
    *)
      printf 'refused to clean unsafe path %s (not under %s)\n' \
        "${worktree_path}" "${expected_prefix}" \
        >> "${RUN_DIR}/cleanup_log.txt" 2>/dev/null || true
      ;;
  esac
fi

# Drop the .current_rid sentinel so the next setup_run starts fresh.
rm -f "${DIP_ROOT}/.current_rid" 2>/dev/null || true

printf 'worktree-cleaned'
