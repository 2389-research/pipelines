#!/bin/sh
# init_iter_counter.sh — set the run's iter counter to 1 and emit the
# Implementer's prompt context.
# Emits: iter-init-ok (line 1) + delimited <plan>, <feedback>, <iter>,
# <repo_conventions> blocks (the rest of stdout).
#
# Why the context blocks: the Implementer agent's upstream node in the .dip
# is THIS tool, so ctx.last_response that the agent sees is THIS tool's
# stdout. Without the embedded blocks the implementer's prompt contract
# (read the plan, address prior feedback) would be unfulfillable — the
# upstream PersistPlan stdout was overwritten by CreateWorktree + this
# tool before it reached the agent. Same shape of fix as fetch_pr_context
# does for the squad reviewers.
#
# The counter is observational; the engine bounds restarts via max_restarts
# in defaults. inc_iter_counter.sh emits iter-next while N<max_iters,
# iter-exhausted otherwise.
set -eu

# ---begin-bootstrap-reference---
STATE_ROOT_DEFAULT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop"
if [ -n "${DEV_LOOP_STATE_ROOT:-}" ]; then
  DIP_ROOT="${DEV_LOOP_STATE_ROOT}"
elif [ ! -L "${STATE_ROOT_DEFAULT}/.last_dip_root" ] \
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

# `max_iters` is one of the values that v1 duplicates across this script,
# config/dev_loop.config.yaml, and `defaults max_restarts:` in dev_loop.dip.
# When you change any of them, change all of them — README's "Config"
# section documents the duplication contract. (Runtime YAML loading is a
# follow-up, not a v1 promise.)
max_iters=5
printf '%s' "${max_iters}" > "${RUN_DIR}/max_iters.txt"
printf '1' > "${RUN_DIR}/iter.txt"

# Marker first; the rest of stdout is the Implementer's prompt context.
printf 'iter-init-ok'

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
1
</iter>

<repo_conventions>
${conventions_text}
</repo_conventions>
DATA
