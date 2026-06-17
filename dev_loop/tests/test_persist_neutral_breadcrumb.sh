#!/bin/sh
# test_persist_neutral_breadcrumb.sh — static guard for persist_*.sh breadcrumbs.
#
# Two locks enforced across all 8 persist_*.sh scripts at once (avoids growing
# the bats matrix for the 6 scripts that lack direct per-arm coverage):
#
#   1. Forbidden-literal lock (#61): no executor-specific path strings
#      ("tracker/runs") in comments or printfs. Persist scripts must stay
#      executor-neutral and name only ${DIP_ARTIFACT_DIR}.
#   2. Required-phrase lock (#73): both arms of the unset-vs-stale guard MUST
#      surface the full actionable wording. A future "simplification" that
#      re-collapses the arms or drops the surfaced path would slip past the
#      per-script bats tests on the 6 unwired scripts; this guard catches it
#      everywhere at once.
#
# Run from the repo root: ./dev_loop/tests/test_persist_neutral_breadcrumb.sh
set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="${DIR}/scripts"

if [ ! -d "${SCRIPTS_DIR}" ]; then
  echo "missing dev_loop/scripts/" >&2
  exit 2
fi

# Resolve the persist_*.sh glob explicitly into positional params BEFORE
# calling grep. If the glob ever stops matching (files renamed/moved/relocated
# under a new naming scheme), `grep ... || true` would otherwise swallow the
# "No such file or directory" error and the guard would silently exit 0 —
# weakening the regression lock. Fail loud instead.
set -- "${SCRIPTS_DIR}"/persist_*.sh
if [ "$#" -eq 0 ] || [ ! -e "$1" ]; then
  printf 'FAIL: no persist_*.sh files under %s (guard cannot run)\n' \
    "${SCRIPTS_DIR}" >&2
  exit 2
fi

# Lock 1 — forbidden literal (#61, extended #88 Gap 2).
#
# We need to distinguish grep's three exit codes here:
#   0 → match(es) found     → forbidden literal present, FAIL (lock tripped)
#   1 → no matches          → guard clean, OK
#   2 → grep error          → cannot trust the result, FAIL (don't silently
#                             pass on permission/IO errors)
# A bare `grep ... || true` would collapse 1 and 2 into the same "empty hits,
# print OK" branch — a false-positive for a regression lock.
#
# Coverage extension (#88 Gap 2): the README porting recipe claims the
# PR-ops / iter / worktree / ratchet scripts "need no changes" for a second
# executor. That claim lives or dies on the same `tracker/runs` literal —
# if any of those scripts ever grows a tracker-coupled path string, the
# README lies to the porter. Scan them alongside persist_*.sh under the same
# Lock 1. The named-file list is deliberate (not a glob) — adding a new
# executor-neutral script to dev_loop/scripts/ must be a conscious decision
# that updates BOTH the README porting recipe AND this list.
PR_OPS_SCRIPTS="
push_and_open_pr.sh
recheck_pr_sha.sh
poll_ci.sh
post_squad_comment.sh
merge_pr.sh
inc_iter_counter.sh
create_worktree.sh
ratchet_log.sh
"
# Build the combined arg vector. Persist scripts come from "$@" (the glob
# expansion above), PR-ops scripts are resolved explicitly so a missing file
# trips a hard error rather than silently shrinking the scan. We pre-validate
# each path exists before handing it to grep so a typo in PR_OPS_SCRIPTS
# fails loud here, not as a grep "No such file" warning that "|| true" might
# otherwise swallow.
scan_paths=$(printf '%s\n' "$@")
for s in ${PR_OPS_SCRIPTS}; do
  p="${SCRIPTS_DIR}/${s}"
  if [ ! -f "${p}" ]; then
    printf 'FAIL: porting-contract scan target missing: %s (guard cannot run)\n' \
      "${p}" >&2
    exit 2
  fi
  scan_paths="${scan_paths}
${p}"
done
# Re-set positional params to the combined list. Newline-delimited so paths
# with spaces stay intact (defensive — repo paths today have no spaces, but
# a worktree under /tmp/agent-* could).
OLDIFS=$IFS
IFS='
'
# shellcheck disable=SC2086  # word-splitting on newlines is intentional here
set -- ${scan_paths}
IFS=$OLDIFS

set +e
hits=$(grep -nH -F "tracker/runs" "$@")
grep_rc=$?
set -e

if [ "${grep_rc}" -eq 0 ]; then
  printf 'FAIL: persist_*.sh + PR-ops/iter/worktree/ratchet scripts must not reference executor-specific path strings (see #61, #88):\n%s\n' \
    "${hits}" >&2
  exit 1
elif [ "${grep_rc}" -ne 1 ]; then
  printf 'FAIL: grep exited %d while scanning porting-contract files (guard cannot run)\n' \
    "${grep_rc}" >&2
  exit 2
fi

# Lock 2 — required phrases (#73). Each persist_*.sh MUST contain BOTH the
# unset-arm and stale-arm wording verbatim. We grep -F (fixed string) for the
# full actionable phrase including the trailing question — a regression that
# drops the suffix, mixes the wording, or re-collapses the arms will fail.
#
# Phrases are the canonical operator-facing strings. Update both here and in
# the 8 persist_*.sh scripts together if the wording ever changes.
UNSET_PHRASE='DIP_ARTIFACT_DIR is unset; was setup_run executed?'
STALE_PHRASE='DIP_ARTIFACT_DIR=%s is not a directory; was the artifact dir cleaned up under us?'

# Lock 2 is persist-only: the unset/stale arms surface DIP_ARTIFACT_DIR for
# operators when persist scripts can't find their input. PR-ops/iter/worktree/
# ratchet scripts don't consume DIP_ARTIFACT_DIR — extending Lock 2 to them
# would be a coverage error, not a hardening. Re-glob the persist set here
# (cheap; the glob already validated upstream).
guard_lock2_failed=0
for f in "${SCRIPTS_DIR}"/persist_*.sh; do
  if ! grep -qF "${UNSET_PHRASE}" "${f}"; then
    printf 'FAIL: %s is missing the #73 unset-arm phrase: %s\n' \
      "${f}" "${UNSET_PHRASE}" >&2
    guard_lock2_failed=1
  fi
  if ! grep -qF "${STALE_PHRASE}" "${f}"; then
    printf 'FAIL: %s is missing the #73 stale-arm phrase: %s\n' \
      "${f}" "${STALE_PHRASE}" >&2
    guard_lock2_failed=1
  fi
done
if [ "${guard_lock2_failed}" -ne 0 ]; then
  exit 1
fi

printf 'OK: persist_*.sh + PR-ops/iter/worktree/ratchet scripts breadcrumbs clean (executor-neutral + #73 phrases pinned)\n'
exit 0
