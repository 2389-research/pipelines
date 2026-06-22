#!/bin/sh
# persist_testability_verdict.sh — capture SquadTestability's JSON verdict to disk.
# Emits: persisted-testability | persist-failed (issue #48).
set -eu

# ---begin-bootstrap-reference---
STATE_ROOT_DEFAULT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop"
if [ -n "${DEV_LOOP_STATE_ROOT:-}" ]; then
  DIP_ROOT="${DEV_LOOP_STATE_ROOT}"
elif [ -f "${STATE_ROOT_DEFAULT}/.last_dip_root" ] \
     && [ ! -L "${STATE_ROOT_DEFAULT}/.last_dip_root" ] \
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

# ---begin-persist-verdict-reference---
# This block is BYTE-IDENTICAL across all five persist_*_verdict.sh scripts
# except the two `squad`/`squad_node` declarations below and the literal
# success marker `printf 'persisted-<slug>'` near the end. The marker stays a
# static literal (not `printf 'persisted-%s'`) because `dippin coverage`/`doctor`
# statically extract printf tokens to verify each tool output has a routing
# edge — a format string would surface as the uncovered output `persisted-%s`.
# Like the bootstrap preamble above, the duplication is intentional and enforced
# — see tests/test_persist_verdict_identical.sh, which normalizes those three
# per-squad lines and asserts every copy matches tests/persist_verdict.ref
# (issue #107). The scripts cannot share a sourced lib: tracker inlines each
# `command_file:` body into the .dipx bundle, which does not ship scripts/lib/.
squad='testability'
squad_node='SquadTestability'

# cd to repo top-level so cwd-relative paths (config files, lib
# helpers, .dev_loop_worktree, executor artifact root) resolve
# consistently when the operator invoked tracker from a subdirectory.
# setup_run.sh publishes DEV_LOOP_REPO_ROOT after its own cd;
# downstream nodes run in fresh shells, so re-anchor here.
if [ -n "${DEV_LOOP_REPO_ROOT:-}" ] && [ -d "${DEV_LOOP_REPO_ROOT}" ]; then
  cd "${DEV_LOOP_REPO_ROOT}"
fi

error_sidecar="${RUN_DIR}/persist_${squad}_error.txt"
fail_class="${RUN_DIR}/persist_${squad}_fail_class.txt"

# Post-bootstrap failure trap (issue #48). Every exit-1 site below already
# writes an actionable line to ${error_sidecar}; the trap
# converts the non-zero exit into ctx.tool_marker=persist-failed so the .dip
# can route through CleanupWorktree + RatchetLog rather than halt mid-flight.
# Installed AFTER the bootstrap preamble: a bootstrap exit-1 (no .current_rid /
# missing env / env-is-symlink) signals state corruption so deep that emitting
# persist-failed would just defer the failure to CleanupWorktree's own
# bootstrap, which would re-trip the same error.
# shellcheck disable=SC2154  # rc is assigned inside the single-quoted trap body
trap 'rc=$?
      if [ "${rc}" -ne 0 ]; then
        [ -s "${error_sidecar}" ] \
          || printf "unexpected non-zero exit (rc=%s)\n" "${rc}" \
             > "${error_sidecar}" 2>/dev/null || true
        printf "persist-failed"
        exit 0
      fi' EXIT

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
    > "${error_sidecar}"
  printf 'unset' > "${fail_class}"
  exit 1
elif [ ! -d "${DIP_ARTIFACT_DIR}" ]; then
  printf 'DIP_ARTIFACT_DIR=%s is not a directory; was the artifact dir cleaned up under us?\n' \
    "${DIP_ARTIFACT_DIR}" \
    > "${error_sidecar}"
  printf 'stale' > "${fail_class}"
  exit 1
fi
dip_artifact_dir="${DIP_ARTIFACT_DIR%/}/"

response="${dip_artifact_dir}${squad_node}/response.md"
target="${RUN_DIR}/verdict_${squad}.json"

if [ ! -f "${response}" ]; then
  printf 'response missing at %s\n' "${response}" \
    > "${error_sidecar}"
  printf 'response-missing' > "${fail_class}"
  exit 1
fi

if ! jq '.' < "${response}" > "${target}.tmp" 2> "${error_sidecar}"; then
  printf 'jq-parse' > "${fail_class}"
  exit 1
fi
mv "${target}.tmp" "${target}"

printf 'persisted-testability'
verdict_text=$(cat "${target}")
cat <<DATA

<verdict_${squad}>
${verdict_text}
</verdict_${squad}>
DATA
# ---end-persist-verdict-reference---
