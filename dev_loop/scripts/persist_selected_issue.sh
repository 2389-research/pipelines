#!/bin/sh
# persist_selected_issue.sh — capture SelectNextIssue's JSON output to disk.
# Writes $RUN_DIR/selected_issue.json. ctx.outcome routes the .dip; no marker.
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
    > "${RUN_DIR}/persist_selected_error.txt"
  exit 1
fi

response="${tracker_run_dir}SelectNextIssue/response.md"
target="${RUN_DIR}/selected_issue.json"

if [ ! -f "${response}" ]; then
  printf 'response missing at %s\n' "${response}" \
    > "${RUN_DIR}/persist_selected_error.txt"
  exit 1
fi

if ! jq '.' < "${response}" > "${target}.tmp" 2> "${RUN_DIR}/persist_selected_error.txt"; then
  exit 1
fi
mv "${target}.tmp" "${target}"

# Surface the issue number into a sidecar file for downstream scripts that need it.
jq -r '.issue_number' "${target}" > "${RUN_DIR}/selected_issue_number.txt"

# PlanMinimalPRs (tool_access: none) reads the selected issue via ctx.last_response.
printf 'persisted-selected'
selected_text=$(cat "${target}")
cat <<DATA

---SELECTED_ISSUE_BEGIN---
${selected_text}
---SELECTED_ISSUE_END---
DATA
