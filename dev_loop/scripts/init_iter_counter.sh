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

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then exit 1; fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"
mkdir -p "${RUN_DIR}"

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
1
</iter>

<repo_conventions>
${conventions_text}
</repo_conventions>
DATA
