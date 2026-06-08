#!/bin/sh
# persist_plan.sh — capture PlanMinimalPRs' JSON output to disk.
# Writes $RUN_DIR/plan.json + sidecar branch_name.txt for downstream scripts.
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then exit 1; fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"
mkdir -p "${RUN_DIR}"

TRACKER_ROOT="$(pwd)/.tracker/runs"
# shellcheck disable=SC2012

tracker_run_dir=$(ls -dt "${TRACKER_ROOT}"/*/ 2>/dev/null | head -1)
if [ -z "${tracker_run_dir}" ]; then
  printf 'no tracker run dir under %s\n' "${TRACKER_ROOT}" \
    > "${RUN_DIR}/persist_plan_error.txt"
  exit 1
fi

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

# Sidecar files used by create_worktree, push_and_open_pr, etc.
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
