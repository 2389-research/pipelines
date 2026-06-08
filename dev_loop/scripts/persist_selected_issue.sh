#!/bin/sh
# persist_selected_issue.sh — capture SelectNextIssue's JSON output to disk.
# Writes $RUN_DIR/selected_issue.json. ctx.outcome routes the .dip; no marker.
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then exit 1; fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"
mkdir -p "${RUN_DIR}"

# Resolve tracker's active artifact dir. Hard contract:
#   1. If the per-run env file exists, setup_run.sh ran and was responsible
#      for pinning TRACKER_RUN_DIR there. If TRACKER_RUN_DIR is then missing
#      or invalid, something corrupted the env file — falling back to ls -dt
#      mtime would defeat the concurrency-isolation guarantee and silently
#      route to whichever run finished most recently. Fail closed.
#   2. If the env file does not exist (operator invoked us before setup, or
#      this is a bats fixture without one), use the ls -dt heuristic as a
#      best-effort discovery.
TRACKER_ROOT="$(pwd)/.tracker/runs"
if [ -f "${RUN_DIR}/env" ]; then
  set -a
  # shellcheck disable=SC1091
  . "${RUN_DIR}/env"
  set +a
  if [ -z "${TRACKER_RUN_DIR:-}" ] || [ ! -d "${TRACKER_RUN_DIR}" ]; then
    tracker_run_dir=""
  else
    tracker_run_dir="${TRACKER_RUN_DIR%/}/"
  fi
else
  # shellcheck disable=SC2012
  tracker_run_dir=$(ls -dt "${TRACKER_ROOT}"/*/ 2>/dev/null | head -1)
fi
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

# Surface the issue number into a sidecar file. Validate it is a positive
# integer BEFORE writing — create_worktree and push_and_open_pr substitute
# this value into branch names and commit messages, and `jq -r` emits the
# literal "null" for a missing or null field, which would silently break
# downstream interpolation.
if ! jq -e '.issue_number | type == "number" and . > 0 and . == floor' "${target}" \
     >/dev/null 2>"${RUN_DIR}/persist_selected_error.txt"; then
  printf 'selected_issue.issue_number is missing, non-numeric, or non-positive\n' \
    >> "${RUN_DIR}/persist_selected_error.txt"
  exit 1
fi
jq -r '.issue_number' "${target}" > "${RUN_DIR}/selected_issue_number.txt"

# PlanMinimalPRs (tool_access: none) reads the selected issue via ctx.last_response
# plus a repo snapshot so it can ground changes[].path values against files that
# actually exist (otherwise the planner fabricates paths).
printf 'persisted-selected'
selected_text=$(cat "${target}")

# repo_tree: top-level dirs + recently-touched files. Cap at ~200 entries each
# to keep prompt overhead bounded. Run from $(pwd) which is tracker's workdir
# (the repo root).
repo_top=""
if [ -d .git ]; then
  repo_top=$(git ls-tree --name-only HEAD 2>/dev/null | head -100)
  repo_recent=$(git log -50 --pretty=format: --name-only 2>/dev/null \
    | sed '/^$/d' | sort -u | head -100)
fi

cat <<DATA

<selected_issue>
${selected_text}
</selected_issue>

<repo_tree>
top-level entries:
${repo_top}

most-recently-touched files (last 50 commits):
${repo_recent:-(no recent activity)}
</repo_tree>
DATA
