#!/bin/sh
# inc_iter_counter.sh — bump the iter counter and route the iteration
# back-edge. Also re-emits the Implementer's prompt context (plan, latest
# feedback, current iter number, repo_conventions) on the iter-next path,
# for the same reason init_iter_counter.sh does: the Implementer's upstream
# is this tool, and without the embedded context blocks the agent's prompt
# contract ("read the plan, address must-fix items from the latest squad
# feedback") is unfulfillable.
#
# Emits on the iter-next path: marker on line 1, then the four XML blocks.
# Emits on the iter-exhausted path: marker only (no context — the next
# routing target is CleanupWorktree, which does not need it).
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

if [ ! -f "${RUN_DIR}/iter.txt" ] || [ ! -f "${RUN_DIR}/max_iters.txt" ]; then
  printf 'iter-exhausted'
  exit 0
fi

iter=$(cat "${RUN_DIR}/iter.txt")
max_iters=$(cat "${RUN_DIR}/max_iters.txt")
next=$((iter + 1))

if [ "${next}" -le "${max_iters}" ]; then
  printf '%s' "${next}" > "${RUN_DIR}/iter.txt"
  printf 'iter-next'

  plan_text=$(cat "${RUN_DIR}/plan.json" 2>/dev/null || printf '{}')
  feedback_text=$(cat "${RUN_DIR}/feedback.json" 2>/dev/null || printf '[]')
  LIB_DIR="${DEV_LOOP_LIB_DIR:-dev_loop/scripts/lib}"
  if [ -f "${LIB_DIR}/load_conventions.sh" ]; then
    # shellcheck source=lib/load_conventions.sh
    # shellcheck disable=SC1091
    . "${LIB_DIR}/load_conventions.sh"
    load_conventions
    # shellcheck disable=SC2153
    conventions_text="${CONVENTIONS_TEXT}"
  else
    # Packed-mode fallback (lib not on disk): inline minimal cascade so
    # AGENTS.md / .dev_loop/conventions.md still reach the Implementer.
    _conv_root="${DEV_LOOP_REPO_ROOT:-}"
    if [ -z "${_conv_root}" ]; then
      _conv_root=$(git rev-parse --show-toplevel 2>/dev/null || printf '.')
    fi
    conventions_text=""
    for _p in \
        "${DEV_LOOP_CONVENTIONS_FILE:-}" \
        "${_conv_root}/.dev_loop/conventions.md" \
        "${_conv_root}/AGENTS.md" \
        "${_conv_root}/CLAUDE.md" \
        "${_conv_root}/CONVENTIONS.md"; do
      if [ -n "${_p}" ] && [ -r "${_p}" ]; then
        conventions_text=$(cat "${_p}" 2>/dev/null || true)
        [ -n "${conventions_text}" ] && break
      fi
    done
    if [ -z "${conventions_text}" ]; then
      conventions_text='(no conventions found)'
    fi
    unset _conv_root _p
  fi

  cat <<DATA

<plan>
${plan_text}
</plan>

<feedback>
${feedback_text}
</feedback>

<iter>
${next}
</iter>

<repo_conventions>
${conventions_text}
</repo_conventions>
DATA
else
  printf 'iter-exhausted'
fi
