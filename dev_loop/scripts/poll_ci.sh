#!/bin/sh
# poll_ci.sh — poll GitHub Actions until checks settle, time out, or run.
# Emits: ci-success | ci-failed | ci-timeout | ci-no-checks
#
# Defaults: poll every 30s for up to 20 minutes. Overridable via
# DEV_LOOP_CI_POLL_INTERVAL / DEV_LOOP_CI_POLL_TIMEOUT env vars (in seconds).
#
# Reads `bucket` from `gh pr checks --json` — the resolved outcome bucket
# (`fail | pass | pending | skipping | cancel`). Fails closed: any settled
# bucket other than `pass` or `skipping` routes to ci-failed (covers
# action_required, startup_failure, stale, neutral, cancelled, etc.).
# gh exits 8 when any check is still pending; that exit code is treated as
# "still polling" rather than a hard error.
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
  set +e
  checks=$(gh pr checks "${pr_num}" --json bucket,state,name,workflow 2>/dev/null)
  rc=$?
  set -e

  # gh exit codes: 0 = settled, 8 = pending. Anything else = real error.
  if [ "${rc}" -ne 0 ] && [ "${rc}" -ne 8 ]; then
    printf 'ci-no-checks'
    exit 0
  fi

  # Empty / unparseable response.
  if [ -z "${checks}" ]; then
    checks='[]'
  fi
  printf '%s' "${checks}" > "${RUN_DIR}/ci_checks.json"

  count=$(printf '%s' "${checks}" | jq 'length' 2>/dev/null || printf '0')
  if [ "${count}" -eq 0 ]; then
    printf 'ci-no-checks'
    exit 0
  fi

  # Any pending? Keep polling.
  pending=$(printf '%s' "${checks}" \
    | jq '[.[] | select(.bucket == "pending")] | length' 2>/dev/null \
    || printf '0')
  if [ "${pending}" -gt 0 ]; then
    sleep "${interval}"
    elapsed=$((elapsed + interval))
    continue
  fi

  # All settled. ci-success only when every check is `pass` or `skipping`;
  # anything else (fail / cancel / action_required / stale / neutral etc.)
  # routes to ci-failed.
  nonpass=$(printf '%s' "${checks}" \
    | jq '[.[] | select(.bucket != "pass" and .bucket != "skipping")] | length' 2>/dev/null \
    || printf '1')
  if [ "${nonpass}" -gt 0 ]; then
    printf 'ci-failed'
  else
    printf 'ci-success'
  fi
  exit 0
done

printf 'ci-timeout'
