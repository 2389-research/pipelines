#!/bin/sh
# recheck_pr_sha.sh — compare the PR's current HEAD SHA against the value
# pinned at the start of this iter. Detects force-pushes between squad review
# and merge gate. Emits: sha-same | sha-drifted
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then
  printf 'sha-drifted'
  exit 0
fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"

# shellcheck disable=SC1091
if [ -f "${RUN_DIR}/env" ]; then
  set -a; . "${RUN_DIR}/env"; set +a
fi
export GH_REPO="${GH_REPO:-2389-research/pipelines}"

if [ ! -f "${RUN_DIR}/pr_head_sha.txt" ] || [ ! -f "${RUN_DIR}/pr_number.txt" ]; then
  printf 'sha-drifted'
  exit 0
fi
pinned=$(cat "${RUN_DIR}/pr_head_sha.txt")
pr_num=$(cat "${RUN_DIR}/pr_number.txt")

current=$(gh pr view "${pr_num}" --json headRefOid --jq '.headRefOid' 2>/dev/null) \
  || { printf 'sha-drifted'; exit 0; }

if [ "${pinned}" = "${current}" ]; then
  printf 'sha-same'
else
  printf '%s\n' "${current}" > "${RUN_DIR}/pr_head_sha_drift.txt"
  printf 'sha-drifted'
fi
