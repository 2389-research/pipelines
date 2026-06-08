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
# prompts at summary:medium fidelity).
#
# Sections are XML-tagged. repo_conventions is loaded from
# dev_loop/config/repo_conventions.md so the squad personas stay universal
# (no project-specific knowledge baked into the persona prompts themselves).
printf 'pr-context-ok'
diff_text=$(cat "${RUN_DIR}/pr_diff.txt" 2>/dev/null || true)
plan_text=$(cat "${RUN_DIR}/plan.json" 2>/dev/null || printf '{}')
feedback_text=$(cat "${RUN_DIR}/feedback.json" 2>/dev/null || printf '[]')

# Locate the conventions file relative to the .dip's script dir. tracker's
# workdir is typically the repo root, so this resolves there. Falls back to
# a minimal stub if missing so reviewers still get a verdict.
conventions_path="dev_loop/config/repo_conventions.md"
if [ -f "${conventions_path}" ]; then
  conventions_text=$(cat "${conventions_path}")
else
  conventions_text='(no repo_conventions.md found; reviewers, fall back to general programming sense and the plan + diff)'
fi

cat <<DATA

<pr_diff>
${diff_text}
</pr_diff>

<plan>
${plan_text}
</plan>

<feedback>
${feedback_text}
</feedback>

<repo_conventions>
${conventions_text}
</repo_conventions>
DATA
