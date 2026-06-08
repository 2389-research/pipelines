#!/bin/sh
# post_squad_comment.sh — post the synthesizer's summary as a PR comment so
# the next iter has feedback visible on the PR thread. Always exits with the
# comment-posted marker (the comment itself is best-effort).
# Emits: comment-posted
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then
  printf 'comment-posted'
  exit 0
fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"

# shellcheck disable=SC1091
if [ -f "${RUN_DIR}/env" ]; then
  set -a; . "${RUN_DIR}/env"; set +a
fi
export GH_REPO="${GH_REPO:-2389-research/pipelines}"

if [ ! -f "${RUN_DIR}/pr_number.txt" ] || [ ! -f "${RUN_DIR}/synthesis.json" ]; then
  printf 'comment-posted'
  exit 0
fi

pr_num=$(cat "${RUN_DIR}/pr_number.txt")
body_file="${RUN_DIR}/squad_comment.md"
{
  printf '## dev_loop squad review\n\n'
  jq -r '.summary' "${RUN_DIR}/synthesis.json"
  printf '\n\n<sub>auto-posted by dev_loop; iter=%s</sub>\n' \
    "$(cat "${RUN_DIR}/iter.txt" 2>/dev/null || printf '?')"
} > "${body_file}"

gh pr comment "${pr_num}" --body-file "${body_file}" > /dev/null 2>&1 || true

printf 'comment-posted'
