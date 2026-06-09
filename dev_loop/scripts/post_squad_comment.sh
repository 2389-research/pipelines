#!/bin/sh
# post_squad_comment.sh — post the synthesizer's summary as a PR comment so
# the next iter has feedback visible on the PR thread. Always exits with the
# comment-posted marker (the comment itself is best-effort).
# Emits: comment-posted
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
