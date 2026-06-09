#!/bin/sh
# persist_plan.sh — capture PlanMinimalPRs' JSON output to disk.
# Writes $RUN_DIR/plan.json + sidecar branch_name.txt for downstream scripts.
set -eu

# ---begin-bootstrap-reference---
STATE_ROOT_DEFAULT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop"
DIP_ROOT="${DEV_LOOP_STATE_ROOT:-${STATE_ROOT_DEFAULT}}"
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

# Resolve tracker's active artifact dir. setup_run.sh pins TRACKER_RUN_DIR in
# the env file; if it's missing or invalid, fail closed rather than falling
# back to ls -dt mtime (which would silently route to whichever run finished
# most recently, defeating concurrency isolation).
TRACKER_ROOT="$(pwd)/.tracker/runs"
if [ -z "${TRACKER_RUN_DIR:-}" ] || [ ! -d "${TRACKER_RUN_DIR}" ]; then
  printf 'no tracker run dir under %s\n' "${TRACKER_ROOT}" \
    > "${RUN_DIR}/persist_plan_error.txt"
  exit 1
fi
tracker_run_dir="${TRACKER_RUN_DIR%/}/"

response="${tracker_run_dir}PlanMinimalPRs/response.md"
target="${RUN_DIR}/plan.json"

if [ ! -f "${response}" ]; then
  printf 'response missing at %s\n' "${response}" \
    > "${RUN_DIR}/persist_plan_error.txt"
  exit 1
fi

if ! jq '.' < "${response}" > "${target}.tmp" 2> "${RUN_DIR}/persist_plan_error.txt"; then
  exit 1
fi
mv "${target}.tmp" "${target}"

# Sidecar files used by create_worktree, push_and_open_pr, etc. Validate
# each field is a non-empty string before writing — `jq -r` emits the literal
# "null" for a missing/null field, which would silently propagate into branch
# names (create_worktree) and commit messages (push_and_open_pr).
# persist_selected_issue.sh applies the same gate for issue_number.
for field in branch_name pr_title pr_body; do
  if ! jq -e ".${field} | type == \"string\" and length > 0" "${target}" \
       >/dev/null 2>"${RUN_DIR}/persist_plan_error.txt"; then
    printf 'plan.%s is missing, null, or empty\n' "${field}" \
      >> "${RUN_DIR}/persist_plan_error.txt"
    exit 1
  fi
done
jq -r '.branch_name' "${target}" > "${RUN_DIR}/branch_name.txt"
jq -r '.pr_title'    "${target}" > "${RUN_DIR}/pr_title.txt"
jq -r '.pr_body'     "${target}" > "${RUN_DIR}/pr_body.txt"

# Implementer reads the plan via ctx.last_response too — even though it has
# disk read access, surfacing it in ctx keeps the prompt self-contained.
printf 'persisted-plan'
plan_text=$(cat "${target}")
cat <<DATA

<plan>
${plan_text}
</plan>
DATA
