#!/bin/sh
# init_iter_counter.sh — set the run's iter counter to 1.
# Emits: iter-init-ok
#
# The counter is observational; the engine bounds restarts via max_restarts in
# defaults. inc_iter_counter.sh emits iter-next while N<max_iters, iter-exhausted
# otherwise.
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then exit 1; fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"
mkdir -p "${RUN_DIR}"

# max_iters comes from config/dev_loop.config.yaml; written by setup_run.sh into
# $RUN_DIR/env (forthcoming). For now, hardcode the same value the .dip uses.
max_iters=5
printf '%s' "${max_iters}" > "${RUN_DIR}/max_iters.txt"
printf '1' > "${RUN_DIR}/iter.txt"

printf 'iter-init-ok'
