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

# ---begin-bootstrap-reference---
STATE_ROOT_DEFAULT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop"
if [ -n "${DEV_LOOP_STATE_ROOT:-}" ]; then
  DIP_ROOT="${DEV_LOOP_STATE_ROOT}"
elif [ -f "${STATE_ROOT_DEFAULT}/.last_dip_root" ] \
     && [ ! -L "${STATE_ROOT_DEFAULT}/.last_dip_root" ] \
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

if [ ! -f "${RUN_DIR}/pr_number.txt" ]; then
  printf 'ci-no-checks'
  exit 0
fi
pr_num=$(cat "${RUN_DIR}/pr_number.txt")

# Validate env-var overrides. Non-numeric inputs would crash the arithmetic
# `$((elapsed + interval))`; interval=0 would spin the loop with no sleep.
# Fall back to the documented defaults whenever the override is invalid and
# log the rejection (so an operator who typo'd the env var can find out).
case "${DEV_LOOP_CI_POLL_INTERVAL:-30}" in
  *[!0-9]*|'') interval=30 ;;
  *) interval="${DEV_LOOP_CI_POLL_INTERVAL:-30}" ;;
esac
if [ "${interval}" -lt 1 ]; then interval=30; fi
case "${DEV_LOOP_CI_POLL_TIMEOUT:-1200}" in
  *[!0-9]*|'') timeout=1200 ;;
  *) timeout="${DEV_LOOP_CI_POLL_TIMEOUT:-1200}" ;;
esac
if [ "${timeout}" -lt 1 ]; then timeout=1200; fi
if [ "${interval}" != "${DEV_LOOP_CI_POLL_INTERVAL:-30}" ] \
   || [ "${timeout}" != "${DEV_LOOP_CI_POLL_TIMEOUT:-1200}" ]; then
  {
    printf 'invalid DEV_LOOP_CI_POLL_INTERVAL=%s or DEV_LOOP_CI_POLL_TIMEOUT=%s; using defaults interval=%s timeout=%s\n' \
      "${DEV_LOOP_CI_POLL_INTERVAL:-}" "${DEV_LOOP_CI_POLL_TIMEOUT:-}" \
      "${interval}" "${timeout}"
  } >> "${RUN_DIR}/poll_ci_error.txt" 2>/dev/null || true
fi
elapsed=0

while [ "${elapsed}" -lt "${timeout}" ]; do
  set +e
  checks=$(gh pr checks "${pr_num}" --json bucket,state,name,workflow \
             2>"${RUN_DIR}/poll_ci_error.txt.tmp")
  rc=$?
  set -e

  # gh exit codes: 0 = settled, 8 = pending. Anything else = real error.
  if [ "${rc}" -ne 0 ] && [ "${rc}" -ne 8 ]; then
    # Capture gh's stderr alongside the rc so the operator can distinguish
    # "repo has no checks" from "auth/network/permission error". The ratchet
    # would otherwise mark every gh hard error as ci-no-checks, hiding the
    # underlying cause.
    {
      printf 'gh pr checks exited %s\n' "${rc}"
      cat "${RUN_DIR}/poll_ci_error.txt.tmp" 2>/dev/null || true
    } > "${RUN_DIR}/poll_ci_error.txt"
    rm -f "${RUN_DIR}/poll_ci_error.txt.tmp"
    printf 'ci-no-checks'
    exit 0
  fi
  rm -f "${RUN_DIR}/poll_ci_error.txt.tmp"

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
