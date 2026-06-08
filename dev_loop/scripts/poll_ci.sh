#!/bin/sh
# poll_ci.sh — poll GitHub Actions until checks settle, time out, or run.
# Emits: ci-success | ci-failed | ci-timeout | ci-no-checks
#
# Defaults: poll every 30s for up to 20 minutes. Overridable via
# DEV_LOOP_CI_POLL_INTERVAL / DEV_LOOP_CI_POLL_TIMEOUT env vars (in seconds).
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then
  printf 'ci-no-checks'
  exit 0
fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"

# shellcheck disable=SC1091
if [ -f "${RUN_DIR}/env" ]; then
  set -a; . "${RUN_DIR}/env"; set +a
fi
export GH_REPO="${GH_REPO:-2389-research/pipelines}"

if [ ! -f "${RUN_DIR}/pr_number.txt" ]; then
  printf 'ci-no-checks'
  exit 0
fi
pr_num=$(cat "${RUN_DIR}/pr_number.txt")

interval="${DEV_LOOP_CI_POLL_INTERVAL:-30}"
timeout="${DEV_LOOP_CI_POLL_TIMEOUT:-1200}"
elapsed=0

while [ "${elapsed}" -lt "${timeout}" ]; do
  checks=$(gh pr checks "${pr_num}" --json state,conclusion 2>/dev/null || printf '[]')
  printf '%s' "${checks}" > "${RUN_DIR}/ci_checks.json"

  count=$(printf '%s' "${checks}" | jq 'length' 2>/dev/null || printf '0')
  if [ "${count}" -eq 0 ]; then
    printf 'ci-no-checks'
    exit 0
  fi

  in_progress=$(printf '%s' "${checks}" \
    | jq '[.[] | select(.state == "IN_PROGRESS" or .state == "QUEUED" or .state == "PENDING")] | length' 2>/dev/null \
    || printf '0')
  if [ "${in_progress}" -eq 0 ]; then
    failed=$(printf '%s' "${checks}" \
      | jq '[.[] | select(.conclusion == "FAILURE" or .conclusion == "TIMED_OUT" or .conclusion == "CANCELLED")] | length' 2>/dev/null \
      || printf '0')
    if [ "${failed}" -gt 0 ]; then
      printf 'ci-failed'
    else
      printf 'ci-success'
    fi
    exit 0
  fi

  sleep "${interval}"
  elapsed=$((elapsed + interval))
done

printf 'ci-timeout'
