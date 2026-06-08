#!/bin/sh
# persist_plan.sh — capture PlanMinimalPRs' JSON output to disk.
# Writes $RUN_DIR/plan.json + sidecar branch_name.txt for downstream scripts.
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
