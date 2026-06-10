#!/bin/sh
# persist_selected_issue.sh — capture SelectNextIssue's JSON output to disk.
# Writes $RUN_DIR/selected_issue.json + sidecar selected_issue_number.txt.
# Emits: persisted-selected | persist-failed (issue #48).
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

# Post-bootstrap failure trap (issue #48). Every exit-1 site below already
# writes an actionable line to $RUN_DIR/persist_selected_error.txt; the trap
# converts the non-zero exit into ctx.tool_marker=persist-failed so the .dip
# can route through CleanupWorktree + RatchetLog rather than halt mid-flight.
# Installed AFTER the bootstrap preamble: a bootstrap exit-1 (no .current_rid /
# missing env / env-is-symlink) signals state corruption so deep that emitting
# persist-failed would just defer the failure to CleanupWorktree's own
# bootstrap, which would re-trip the same error.
# shellcheck disable=SC2154  # rc is assigned inside the single-quoted trap body
trap 'rc=$?
      if [ "${rc}" -ne 0 ]; then
        [ -s "${RUN_DIR}/persist_selected_error.txt" ] \
          || printf "unexpected non-zero exit (rc=%s)\n" "${rc}" \
             > "${RUN_DIR}/persist_selected_error.txt" 2>/dev/null || true
        printf "persist-failed"
        exit 0
      fi' EXIT

# Resolve tracker's active artifact dir. setup_run.sh pins TRACKER_RUN_DIR in
# the env file; if it's missing or invalid, fail closed rather than falling
# back to ls -dt mtime (which would silently route to whichever run finished
# most recently, defeating concurrency isolation).
TRACKER_ROOT="$(pwd)/.tracker/runs"
if [ -z "${TRACKER_RUN_DIR:-}" ] || [ ! -d "${TRACKER_RUN_DIR}" ]; then
  printf 'no tracker run dir under %s\n' "${TRACKER_ROOT}" \
    > "${RUN_DIR}/persist_selected_error.txt"
  exit 1
fi
tracker_run_dir="${TRACKER_RUN_DIR%/}/"

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
