#!/bin/sh
# cleanup_worktree.sh — idempotently remove the run's worktree + symlink.
# Emits: worktree-cleaned (always — even when there's nothing to clean)
#
# Idempotent: runs from every exit path AND from each agent's fallback_target.
# Never fails the pipeline; ratchet_log records the final disposition.
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

# cd to repo top-level so cwd-relative paths (config files, lib helpers,
# .dev_loop_worktree, .tracker/runs) resolve consistently when the
# operator invoked tracker from a subdirectory. setup_run.sh publishes
# DEV_LOOP_REPO_ROOT after its own cd; downstream nodes run in fresh
# shells at tracker's original cwd, so re-anchor here.
if [ -n "${DEV_LOOP_REPO_ROOT:-}" ] && [ -d "${DEV_LOOP_REPO_ROOT}" ]; then
  cd "${DEV_LOOP_REPO_ROOT}"
fi

symlink="$(pwd)/.dev_loop_worktree"
# Only unlink when it IS the symlink we created. If a user has a real
# directory at this path we leave it alone (and let the rest of cleanup
# proceed) — never `rm -rf` an unrelated dir that happens to match the name.
if [ -L "${symlink}" ]; then
  rm -f "${symlink}" 2>/dev/null || true
elif [ -e "${symlink}" ]; then
  printf 'refused to clean .dev_loop_worktree (not a symlink)\n' \
    >> "${RUN_DIR}/cleanup_log.txt" 2>/dev/null || true
fi

if [ -f "${RUN_DIR}/worktree.path" ]; then
  worktree_path=$(cat "${RUN_DIR}/worktree.path")
  # Canonicalize both paths before the prefix check. A naive `case` against
  # the lexical string lets traversal segments like
  # "${RUN_DIR}/worktree/../../somewhere" pass the prefix check while
  # actually pointing outside RUN_DIR — `rm -rf` would then delete the
  # wrong thing. `readlink -f` resolves both symlinks AND `..` segments
  # before comparison. Linux-only, which matches dev_loop's existing pin.
  expected_prefix=$(readlink -f "${RUN_DIR}/worktree" 2>/dev/null \
                    || printf '%s' "${RUN_DIR}/worktree")
  canonical_path=$(readlink -f "${worktree_path}" 2>/dev/null \
                   || printf '%s' "${worktree_path}")
  case "${canonical_path}" in
    "${expected_prefix}"|"${expected_prefix}"/*)
      if [ -d "${worktree_path}" ]; then
        git worktree remove --force "${worktree_path}" 2>/dev/null \
          || rm -rf "${worktree_path}"
      fi
      printf 'cleaned %s\n' "${worktree_path}" \
        >> "${RUN_DIR}/cleanup_log.txt" 2>/dev/null || true
      ;;
    *)
      printf 'refused to clean unsafe path %s (canonical=%s; not under %s)\n' \
        "${worktree_path}" "${canonical_path}" "${expected_prefix}" \
        >> "${RUN_DIR}/cleanup_log.txt" 2>/dev/null || true
      ;;
  esac
fi

# Release the concurrency lock so the next dev_loop run can start fresh.
# .current_rid persists; the next setup_run atomically overwrites it.
rm -rf "${DIP_ROOT}/.dev_loop.lock" 2>/dev/null || true

printf 'worktree-cleaned'
