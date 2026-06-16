#!/bin/sh
# persist_synthesis.sh — capture SquadSynthesizer's JSON output and emit the
# routing marker that drives the merge / iterate / abandon branch in dev_loop.dip.
# Emits: synthesized-approved | synthesized-changes_requested | synthesized-abandoned
#
# Outputs:
#   $RUN_DIR/synthesis.json  — full synthesis output (verbatim from the agent)
#   $RUN_DIR/feedback.json   — must_fix list seeded into the next iter's implementer
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

# cd to repo top-level so cwd-relative paths (config files, lib
# helpers, .dev_loop_worktree, executor artifact root) resolve
# consistently when the operator invoked tracker from a subdirectory.
# setup_run.sh publishes DEV_LOOP_REPO_ROOT after its own cd;
# downstream nodes run in fresh shells, so re-anchor here.
if [ -n "${DEV_LOOP_REPO_ROOT:-}" ] && [ -d "${DEV_LOOP_REPO_ROOT}" ]; then
  cd "${DEV_LOOP_REPO_ROOT}"
fi

# A non-zero exit anywhere routes to CleanupWorktree via the fail edge on the
# SquadSynthesizer agent fallback; we choose abandoned as the conservative
# default if the response can't be read.
trap 'if [ $? -ne 0 ]; then printf "synthesized-abandoned"; exit 0; fi' EXIT

# Resolve the dip executor's active artifact dir. setup_run.sh pins DIP_ARTIFACT_DIR
# in the env file; if it's missing or invalid, fail closed rather than falling
# back to ls -dt mtime (which would silently route to whichever run finished
# most recently, defeating concurrency isolation). The breadcrumb names the
# env var (the actionable knob), not the executor's on-disk layout — see #61.
# Issue #73: split unset vs set-but-stale so the operator can tell
# setup_run-skipped from cleanup-race apart without opening ${RUN_DIR}/env.
# The stale arm prints the surfaced path; safe per PR #65's security review
# (reject_special in setup_run.sh strips NL/CR before the env file write).
if [ -z "${DIP_ARTIFACT_DIR:-}" ]; then
  printf 'DIP_ARTIFACT_DIR is unset; was setup_run executed?\n' \
    > "${RUN_DIR}/persist_synthesis_error.txt"
  printf 'unset' > "${RUN_DIR}/persist_synthesis_fail_class.txt"
  exit 1
elif [ ! -d "${DIP_ARTIFACT_DIR}" ]; then
  printf 'DIP_ARTIFACT_DIR=%s is not a directory; was the artifact dir cleaned up under us?\n' \
    "${DIP_ARTIFACT_DIR}" \
    > "${RUN_DIR}/persist_synthesis_error.txt"
  printf 'stale' > "${RUN_DIR}/persist_synthesis_fail_class.txt"
  exit 1
fi
dip_artifact_dir="${DIP_ARTIFACT_DIR%/}/"

response="${dip_artifact_dir}SquadSynthesizer/response.md"
if [ ! -f "${response}" ]; then
  printf 'response missing at %s\n' "${response}" \
    > "${RUN_DIR}/persist_synthesis_error.txt"
  printf 'response-missing' > "${RUN_DIR}/persist_synthesis_fail_class.txt"
  exit 1
fi

if ! jq '.' < "${response}" > "${RUN_DIR}/synthesis.json.tmp" \
   2> "${RUN_DIR}/persist_synthesis_error.txt"; then
  printf 'jq-parse' > "${RUN_DIR}/persist_synthesis_fail_class.txt"
  exit 1
fi
mv "${RUN_DIR}/synthesis.json.tmp" "${RUN_DIR}/synthesis.json"

# Extract the must-fix list into a separate file for the next iter's implementer
# prompt (synthesizer guarantees feedback>=1 when outcome=changes_requested).
jq '.feedback // []' "${RUN_DIR}/synthesis.json" > "${RUN_DIR}/feedback.json"

outcome=$(jq -r '.outcome' "${RUN_DIR}/synthesis.json")
# Enumerate markers explicitly so dippin's coverage analyzer can match the
# literal-marker edges in dev_loop.dip (it does not reason about printf format
# strings — it scans the script body for literal marker strings).
case "${outcome}" in
  approved)
    printf 'synthesized-approved'
    ;;
  changes_requested)
    # Synthesizer's contract: changes_requested REQUIRES non-empty feedback so
    # the next iter's Implementer has something to act on. If the synthesizer
    # broke contract (empty feedback array or missing key), fall back to
    # synthesized-abandoned with a clear breadcrumb — looping with no feedback
    # would loop forever.
    fb_len=$(jq -r '(.feedback // []) | length' "${RUN_DIR}/synthesis.json")
    if [ "${fb_len}" = "0" ]; then
      printf 'synthesizer broke contract: outcome=changes_requested but feedback is empty/missing\n' \
        >> "${RUN_DIR}/persist_synthesis_error.txt"
      printf 'synthesized-abandoned'
    else
      printf 'synthesized-changes_requested'
    fi
    ;;
  abandoned)
    printf 'synthesized-abandoned'
    ;;
  *)
    printf 'unknown outcome: %s\n' "${outcome}" >> "${RUN_DIR}/persist_synthesis_error.txt"
    printf 'synthesized-abandoned'
    ;;
esac
