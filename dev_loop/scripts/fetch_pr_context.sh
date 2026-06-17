#!/bin/sh
# fetch_pr_context.sh — refresh PR state at the top of each iter.
# Pins the HEAD SHA so recheck_pr_sha can detect external force-pushes.
# Emits: pr-context-ok | pr-closed | pr-merged-externally
set -eu

# ---begin-bootstrap-reference---
STATE_ROOT_DEFAULT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop"
if [ -n "${DEV_LOOP_STATE_ROOT:-}" ]; then
  DIP_ROOT="${DEV_LOOP_STATE_ROOT}"
elif [ ! -L "${STATE_ROOT_DEFAULT}/.last_dip_root" ] \
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

# Fail closed: if we cannot fetch the diff, do NOT emit pr-context-ok with an
# empty payload. The squad would then "review" an empty diff and potentially
# approve it. Route to pr-closed (cleanup path) instead and record the error.
if ! gh pr diff "${pr_num}" > "${RUN_DIR}/pr_diff.txt" \
     2> "${RUN_DIR}/pr_diff_error.txt"; then
  printf 'pr-closed'
  exit 0
fi
if [ ! -s "${RUN_DIR}/pr_diff.txt" ]; then
  printf 'empty pr_diff for PR #%s\n' "${pr_num}" >> "${RUN_DIR}/pr_diff_error.txt"
  printf 'pr-closed'
  exit 0
fi

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
LIB_DIR="${DEV_LOOP_LIB_DIR:-dev_loop/scripts/lib}"
if [ -f "${LIB_DIR}/load_conventions.sh" ]; then
  # shellcheck source=lib/load_conventions.sh
  # shellcheck disable=SC1091
  . "${LIB_DIR}/load_conventions.sh"
  load_conventions
  # shellcheck disable=SC2153
  conventions_text="${CONVENTIONS_TEXT}"
else
  # Packed-mode fallback: the lib helper isn't on disk (typical of
  # `tracker ~/dl.dipx` against a repo with no dev_loop/ tree). Inline a
  # minimal cascade so reviewers still get project-specific rules when
  # AGENTS.md / .dev_loop/conventions.md / etc. are present.
  _conv_root="${DEV_LOOP_REPO_ROOT:-}"
  if [ -z "${_conv_root}" ]; then
    _conv_root=$(git rev-parse --show-toplevel 2>/dev/null || printf '.')
  fi
  conventions_text=""
  for _p in \
      "${DEV_LOOP_CONVENTIONS_FILE:-}" \
      "${_conv_root}/.dev_loop/conventions.md" \
      "${_conv_root}/AGENTS.md" \
      "${_conv_root}/CLAUDE.md" \
      "${_conv_root}/CONVENTIONS.md"; do
    if [ -n "${_p}" ] && [ -r "${_p}" ]; then
      conventions_text=$(cat "${_p}" 2>/dev/null || true)
      [ -n "${conventions_text}" ] && break
    fi
  done
  if [ -z "${conventions_text}" ]; then
    conventions_text='(no conventions found; reviewers, fall back to general programming sense and the plan + diff)'
  fi
  unset _conv_root _p
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
