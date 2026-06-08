#!/bin/sh
# ratchet_log.sh — append a one-line summary of this run to the global ratchet.
# Emits: ratcheted (always — best-effort).
#
# Ratchet file: $DIP_ROOT/ratchet.tsv
#   Columns: rid<TAB>iso_timestamp<TAB>issue_number<TAB>branch<TAB>outcome<TAB>iters_used<TAB>notes
set -eu

DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"
mkdir -p "${DIP_ROOT}"
RATCHET="${DIP_ROOT}/ratchet.tsv"
if [ ! -f "${RATCHET}" ]; then
  printf 'rid\tts\tissue\tbranch\toutcome\titers_used\tnotes\n' > "${RATCHET}"
fi

rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
if [ -z "${rid}" ]; then
  # cleanup_worktree drops .current_rid; look for the most-recent run dir.
  # shellcheck disable=SC2012
  recent_dir=$(ls -dt "${DIP_ROOT}/runs"/*/ 2>/dev/null | head -1)
  if [ -n "${recent_dir}" ]; then
    rid=$(basename "${recent_dir}")
  fi
fi
if [ -z "${rid}" ]; then
  printf 'ratcheted'
  exit 0
fi
RUN_DIR="${DIP_ROOT}/runs/${rid}"

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
