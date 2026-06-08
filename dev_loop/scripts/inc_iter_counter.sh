#!/bin/sh
# inc_iter_counter.sh — bump the iter counter and route the iteration back-edge.
# Emits: iter-next (when iter+1 <= max_iters) | iter-exhausted (otherwise)
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
else
  printf 'iter-exhausted'
fi
