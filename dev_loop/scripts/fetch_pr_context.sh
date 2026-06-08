#!/bin/sh
# fetch_pr_context.sh — refresh PR state at the top of each iter.
# Pins the HEAD SHA so recheck_pr_sha can detect external force-pushes.
# Emits: pr-context-ok | pr-closed | pr-merged-externally
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then
  printf 'pr-closed'
  exit 0
fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"

# shellcheck disable=SC1091
if [ -f "${RUN_DIR}/env" ]; then
  set -a; . "${RUN_DIR}/env"; set +a
fi
export GH_REPO="${GH_REPO:-2389-research/pipelines}"

if [ ! -f "${RUN_DIR}/pr_number.txt" ]; then
  printf 'pr-closed'
  exit 0
fi
pr_num=$(cat "${RUN_DIR}/pr_number.txt")

pr_view=$(gh pr view "${pr_num}" \
  --json state,mergedAt,headRefOid,number,url,headRefName,baseRefName 2>/dev/null) \
  || { printf 'pr-closed'; exit 0; }
printf '%s' "${pr_view}" > "${RUN_DIR}/pr_view.json"

state=$(printf '%s' "${pr_view}" | jq -r '.state')
merged_at=$(printf '%s' "${pr_view}" | jq -r '.mergedAt // "null"')

if [ "${state}" = "MERGED" ] || [ "${merged_at}" != "null" ]; then
  printf 'pr-merged-externally'
  exit 0
fi
if [ "${state}" = "CLOSED" ]; then
  printf 'pr-closed'
  exit 0
fi

head_sha=$(printf '%s' "${pr_view}" | jq -r '.headRefOid')
printf '%s' "${head_sha}" > "${RUN_DIR}/pr_head_sha.txt"

gh pr diff "${pr_num}" > "${RUN_DIR}/pr_diff.txt" 2>/dev/null || true

# Emit the marker first so marker_grep (which anchors on whole lines) extracts
# it as ctx.tool_marker. The rest of stdout becomes ctx.tool_stdout and
# downstream agents see it via ctx.last_response (auto-injected into their
# prompts at summary:medium fidelity). Section delimiters are read by the
# shared squad/task.md prompt.
printf 'pr-context-ok'
diff_text=$(cat "${RUN_DIR}/pr_diff.txt" 2>/dev/null || true)
plan_text=$(cat "${RUN_DIR}/plan.json" 2>/dev/null || printf '{}')
feedback_text=$(cat "${RUN_DIR}/feedback.json" 2>/dev/null || printf '[]')
cat <<DATA

---PR_DIFF_BEGIN---
${diff_text}
---PR_DIFF_END---

---PLAN_BEGIN---
${plan_text}
---PLAN_END---

---FEEDBACK_BEGIN---
${feedback_text}
---FEEDBACK_END---
DATA
