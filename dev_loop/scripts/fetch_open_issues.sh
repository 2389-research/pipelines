#!/bin/sh
# fetch_open_issues.sh — pull open issues for the locked repo.
# Emits: fetched-ok | fetch-failed
#
# Outputs:
#   $RUN_DIR/issues.json        — gh JSON list (sorted newest first)
#   $RUN_DIR/issues_count.txt   — integer count of fetched issues
set -eu

# ---begin-bootstrap-reference---
STATE_ROOT_DEFAULT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop"
if [ -n "${DEV_LOOP_STATE_ROOT:-}" ]; then
  DIP_ROOT="${DEV_LOOP_STATE_ROOT}"
elif [ -r "${STATE_ROOT_DEFAULT}/.last_dip_root" ]; then
  DIP_ROOT=$(cat "${STATE_ROOT_DEFAULT}/.last_dip_root" 2>/dev/null || true)
  [ -n "${DIP_ROOT}" ] || DIP_ROOT="${STATE_ROOT_DEFAULT}"
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

emit_failure() {
  printf '%s\n' "$1" > "${RUN_DIR}/fetch_error.txt" 2>/dev/null || true
  printf 'fetch-failed'
  exit 0
}

trap 'if [ $? -ne 0 ]; then printf "fetch-failed"; exit 0; fi' EXIT

if ! gh issue list \
    --repo "${GH_REPO}" \
    --limit 200 \
    --state open \
    --json number,title,url,labels,author,createdAt,body \
    > "${RUN_DIR}/issues.json.tmp" \
    2> "${RUN_DIR}/fetch_error.txt"; then
  err=$(head -c 500 "${RUN_DIR}/fetch_error.txt" 2>/dev/null)
  emit_failure "gh issue list failed for ${GH_REPO:-?}: ${err}"
fi

# Fail closed when gh returned 0 but the JSON is malformed/truncated; the
# silent `|| printf '0'` fallback would otherwise route to fetched-ok with
# an empty issues list, and the planner would proceed on bogus data.
if ! count=$(jq 'length' "${RUN_DIR}/issues.json.tmp" 2>"${RUN_DIR}/fetch_error.txt"); then
  printf 'jq could not parse issues.json.tmp\n' >> "${RUN_DIR}/fetch_error.txt"
  emit_failure "jq parse failed: see fetch_error.txt"
fi

mv "${RUN_DIR}/issues.json.tmp" "${RUN_DIR}/issues.json"
printf '%s' "${count}" > "${RUN_DIR}/issues_count.txt"

printf 'fetched-ok'
