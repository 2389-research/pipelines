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

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then
  printf 'iter-exhausted'
  exit 0
fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"
mkdir -p "${RUN_DIR}"

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
  conventions_path="dev_loop/config/repo_conventions.md"
  if [ -f "${conventions_path}" ]; then
    conventions_text=$(cat "${conventions_path}")
  else
    conventions_text='(no repo_conventions.md found)'
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
