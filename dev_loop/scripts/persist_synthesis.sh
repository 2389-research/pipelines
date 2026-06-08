#!/bin/sh
# persist_synthesis.sh — capture SquadSynthesizer's JSON output and emit the
# routing marker that drives the merge / iterate / abandon branch in dev_loop.dip.
# Emits: synthesized-approved | synthesized-changes_requested | synthesized-abandoned
#
# Outputs:
#   $RUN_DIR/synthesis.json  — full synthesis output (verbatim from the agent)
#   $RUN_DIR/feedback.json   — must_fix list seeded into the next iter's implementer
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then
  printf 'synthesized-abandoned'
  exit 0
fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"
mkdir -p "${RUN_DIR}"

# A non-zero exit anywhere routes to CleanupWorktree via the fail edge on the
# SquadSynthesizer agent fallback; we choose abandoned as the conservative
# default if the response can't be read.
trap 'if [ $? -ne 0 ]; then printf "synthesized-abandoned"; fi' EXIT

TRACKER_ROOT="$(pwd)/.tracker/runs"
# shellcheck disable=SC2012

tracker_run_dir=$(ls -dt "${TRACKER_ROOT}"/*/ 2>/dev/null | head -1)
if [ -z "${tracker_run_dir}" ]; then
  printf 'no tracker run dir under %s\n' "${TRACKER_ROOT}" \
    > "${RUN_DIR}/persist_synthesis_error.txt"
  exit 1
fi

response="${tracker_run_dir}SquadSynthesizer/response.md"
if [ ! -f "${response}" ]; then
  printf 'response missing at %s\n' "${response}" \
    > "${RUN_DIR}/persist_synthesis_error.txt"
  exit 1
fi

if ! jq '.' < "${response}" > "${RUN_DIR}/synthesis.json.tmp" \
   2> "${RUN_DIR}/persist_synthesis_error.txt"; then
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
    printf 'synthesized-changes_requested'
    ;;
  abandoned)
    printf 'synthesized-abandoned'
    ;;
  *)
    printf 'unknown outcome: %s\n' "${outcome}" >> "${RUN_DIR}/persist_synthesis_error.txt"
    printf 'synthesized-abandoned'
    ;;
esac
