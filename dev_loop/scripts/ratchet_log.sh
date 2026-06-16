#!/bin/sh
# ratchet_log.sh — append a one-line summary of this run to the global ratchet.
# Emits: ratcheted (always — best-effort).
#
# Ratchet file: $DIP_ROOT/ratchet.tsv
#   Columns: rid<TAB>iso_timestamp<TAB>issue_number<TAB>branch<TAB>outcome<TAB>iters_used<TAB>notes
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

RATCHET="${DIP_ROOT}/ratchet.tsv"
if [ ! -f "${RATCHET}" ]; then
  printf 'rid\tts\tissue\tbranch\toutcome\titers_used\tnotes\n' > "${RATCHET}"
fi

rid=$(basename "${RUN_DIR}")

issue=$(cat "${RUN_DIR}/selected_issue_number.txt" 2>/dev/null || printf 'unknown')
branch=$(cat "${RUN_DIR}/branch_name.txt" 2>/dev/null || printf 'unknown')
iters_used=$(cat "${RUN_DIR}/iter.txt" 2>/dev/null || printf '0')
if [ -f "${RUN_DIR}/synthesis.json" ]; then
  outcome=$(jq -r '.outcome' "${RUN_DIR}/synthesis.json" 2>/dev/null || printf 'unknown')
else
  outcome='unknown'
fi

# A few inferred outcomes the synthesis.json wouldn't capture.
if [ -f "${RUN_DIR}/merge_log.txt" ]; then
  outcome='merged'
elif [ -f "${RUN_DIR}/merge_block_reason.txt" ]; then
  outcome="merge-blocked-$(cat "${RUN_DIR}/merge_block_reason.txt")"
elif [ -f "${RUN_DIR}/pr_head_sha_drift.txt" ]; then
  outcome='sha-drifted'
elif [ -f "${RUN_DIR}/setup_error.txt" ]; then
  outcome='setup-failed'
elif [ -f "${RUN_DIR}/persist_selected_error.txt" ] \
  || [ -f "${RUN_DIR}/persist_plan_error.txt" ] \
  || [ -f "${RUN_DIR}/persist_pragmatism_error.txt" ] \
  || [ -f "${RUN_DIR}/persist_yagni_error.txt" ] \
  || [ -f "${RUN_DIR}/persist_testability_error.txt" ] \
  || [ -f "${RUN_DIR}/persist_holistic_error.txt" ] \
  || [ -f "${RUN_DIR}/persist_blocker_error.txt" ]; then
  # Any of the seven non-synthesis persist_<flavor>_error.txt sidecars means
  # the matching persist node tripped its post-bootstrap failure path
  # (issue #48). Order matters: setup-failed wins when both files exist
  # (setup is more upstream). Sidecar NAMES already encode WHICH persist
  # node failed — the ratchet outcome stays generic.
  #
  # persist_synthesis_error.txt is DELIBERATELY EXCLUDED. persist_synthesis.sh
  # uses the synthesized-abandoned marker (predates this scheme) and the
  # workflow routes it via the synth_abandoned cleanup edge with that intent.
  # Lumping it into outcome=persist-failed would mismatch the marker the
  # workflow actually emitted.
  #
  # Issue #90: persist_*.sh now also write a structured fail_class sidecar
  # (unset | stale | response-missing | jq-parse | validation) at each exit-1
  # site. When present, surface it as persist-failed-<class> so post-mortems
  # can distinguish failure modes at the marker layer. Same explicit enum as
  # the error-file chain above — synthesis is excluded for the same reason.
  #
  # Pair each fail_class file with the SAME flavor's error file that triggered
  # this branch — never just glob fail_class.txt sidecars. Partial cleanup or
  # operator edits could leave a stale persist_X_fail_class.txt from an earlier
  # run alongside a fresh persist_Y_error.txt, and a blind first-match scan
  # would label outcome with class X (wrong flavor). Walk the same flavor list
  # as the elif condition, first error.txt match wins, read that flavor's
  # sidecar. Older runs / partial cleanup may lack the sidecar — fall back to
  # bare persist-failed.
  fail_class=""
  for flavor in selected plan pragmatism yagni testability holistic blocker; do
    err="${RUN_DIR}/persist_${flavor}_error.txt"
    if [ -f "${err}" ]; then
      fcf="${RUN_DIR}/persist_${flavor}_fail_class.txt"
      if [ -s "${fcf}" ]; then
        fail_class=$(cat "${fcf}" 2>/dev/null || true)
      fi
      break
    fi
  done
  if [ -n "${fail_class}" ]; then
    outcome="persist-failed-${fail_class}"
  else
    outcome='persist-failed'
  fi
fi

notes=""
if [ -f "${RUN_DIR}/gates_error.txt" ]; then
  notes="gates-fail: $(head -1 "${RUN_DIR}/gates_error.txt")"
fi

# Sanitize TSV-breaking control characters in every column before writing.
# A literal tab or newline in any field would break ratchet.tsv's column
# structure and make downstream parsing unreliable. Replace tab/CR/LF with a
# single space.
tsv_safe() { printf '%s' "$1" | tr '\t\r\n' '   '; }
ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
  "$(tsv_safe "${rid}")" \
  "${ts}" \
  "$(tsv_safe "${issue}")" \
  "$(tsv_safe "${branch}")" \
  "$(tsv_safe "${outcome}")" \
  "$(tsv_safe "${iters_used}")" \
  "$(tsv_safe "${notes}")" \
  >> "${RATCHET}"

printf 'ratcheted'
