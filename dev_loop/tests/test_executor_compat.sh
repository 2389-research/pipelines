#!/bin/sh
# test_executor_compat.sh — porting-contract smoke against a stub second executor.
#
# Verifies the dev_loop ↔ executor contract documented in dev_loop/README.md
# "Executor compatibility" + "Porting to a different dip executor". Two
# independent failure modes catch porting-recipe drift:
#
#   1. Stub-executor run-through: the 8 persist_*.sh scripts are invoked
#      against a synthesized DIP_ARTIFACT_DIR (no .tracker/runs on disk
#      anywhere). They must emit their `persisted-*` / `synthesized-*`
#      markers and must NOT reference `tracker` or `.tracker/runs` strings
#      on stdout or in their error-breadcrumb files. This is the runtime
#      side of the contract.
#
#   2. README load-bearing-string lock: the porting recipe enumerates two
#      literal code strings as the porter's edit targets. If either side
#      (README or setup_run.sh) drifts without the other being updated,
#      the recipe lies to the porter. Both halves are pinned.
#
# Run from the repo root: ./dev_loop/tests/test_executor_compat.sh
#
# This is a static + runtime guard — it does NOT modify any production
# script. If the test reveals an actual contract drift, fix the underlying
# code/docs in a separate change; do not relax the assertions here.
set -eu

DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS_DIR="${DIR}/scripts"
README="${DIR}/README.md"
SETUP_RUN="${SCRIPTS_DIR}/setup_run.sh"
FIXTURES="${DIR}/tests/fixtures"

if [ ! -d "${SCRIPTS_DIR}" ] || [ ! -f "${README}" ] || [ ! -f "${SETUP_RUN}" ]; then
  printf 'FAIL: dev_loop tree missing (scripts/ README.md scripts/setup_run.sh)\n' >&2
  exit 2
fi

rc=0
TMPDIR_T=""
# shellcheck disable=SC2317  # invoked indirectly via trap
cleanup() {
  [ -n "${TMPDIR_T}" ] && rm -rf "${TMPDIR_T}"
}
trap cleanup EXIT INT TERM

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  rc=1
}

# -------------------------------------------------------------------------
# Section 1 — README load-bearing-string lock.
#
# Both literals are quoted verbatim in dev_loop/README.md's "Porting to a
# different dip executor" recipe. A refactor on either side (rename the
# variable in setup_run.sh, reorder the prereq loop, reword the recipe
# bullet) trips the lock. The lock is bi-directional on purpose: the bug
# this test guards against is documentation drift, which silently hurts
# only the next porter.
# -------------------------------------------------------------------------

# Load-bearing literal #1 — the discovery-block anchor the porting recipe
# names as the porter's first edit target. Single-quoted intentionally so
# `$(pwd)` is preserved verbatim for the grep target (we are pinning the
# code string as-written, not its expanded form).
# shellcheck disable=SC2016
LIT_DISCOVERY='DIP_ARTIFACT_ROOT="$(pwd)/.tracker/runs"'

# Load-bearing literal #2 — the prereq-tool loop the porting recipe names
# as the porter's second edit target. In setup_run.sh the loop is a single
# line; in README the same span is reflowed across two markdown lines
# inside one backtick-quoted block. Pin the contiguous setup_run.sh form,
# and pin a whitespace-collapsed form against the README so a reflow
# (typical of doc edits) does not trip the lock but a content edit does.
LIT_PREREQ='for cmd in gh jq git tracker yq timeout'

if ! grep -qF "${LIT_DISCOVERY}" "${SETUP_RUN}"; then
  fail "setup_run.sh no longer contains the porting-recipe discovery literal: ${LIT_DISCOVERY}"
fi
if ! grep -qF "${LIT_DISCOVERY}" "${README}"; then
  fail "README porting recipe no longer quotes the discovery literal: ${LIT_DISCOVERY}"
fi
if ! grep -qF "${LIT_PREREQ}" "${SETUP_RUN}"; then
  fail "setup_run.sh no longer contains the porting-recipe prereq loop literal: ${LIT_PREREQ}"
fi
# README form: collapse any run of whitespace (incl. newlines) inside the
# file to a single space, then look for the literal. tr to a single-line
# stream first; grep -F on the collapsed form. This is intentionally
# resilient to markdown reflow but strict on content drift (rename or
# reorder the tools and the assertion trips).
if ! tr '\n' ' ' < "${README}" | tr -s ' ' | grep -qF "${LIT_PREREQ}"; then
  fail "README porting recipe no longer quotes the prereq loop literal: ${LIT_PREREQ}"
fi

# -------------------------------------------------------------------------
# Section 2 — Stub-executor run-through.
#
# Synthesize a per-node artifact directory that looks like what a NON-tracker
# executor would produce: a flat <DIP_ARTIFACT_DIR>/<NodeID>/response.md
# layout, with no .tracker/runs ancestor anywhere on disk. The persist
# scripts must be willing to read it (the contract says they consume
# ${DIP_ARTIFACT_DIR} from the env file, not a discovered path), and must
# not emit tracker-coupled strings on success or failure paths.
# -------------------------------------------------------------------------

TMPDIR_T="$(mktemp -d)"

# Mirror test_helpers.bash's setup_env shape, but with an executor-neutral
# artifact-dir name to make the contract-violation message obvious when the
# assertion below trips.
WORKDIR="${TMPDIR_T}/workdir"
DIP_STATE_ROOT="${TMPDIR_T}/state"
# Deliberately NOT `.tracker/runs`. A second executor would put its
# per-node responses somewhere else; the directory name here is just a
# stand-in for "any other executor's layout".
STUB_ARTIFACT_DIR="${WORKDIR}/.stub-executor/run-abc123"
RID="t-executor-compat-$$"
RUN_DIR="${DIP_STATE_ROOT}/runs/${RID}"

mkdir -p "${WORKDIR}" "${RUN_DIR}" "${STUB_ARTIFACT_DIR}"

# Write the per-run env file the persist scripts will source via the canonical
# bootstrap. The DIP_ARTIFACT_DIR value points at our stub layout.
cat > "${RUN_DIR}/env" <<EOF
GH_REPO='test/test'
BASE_BRANCH='main'
ALLOW_NO_CI='false'
DEV_LOOP_RUN_ID='${RID}'
DEV_LOOP_RUN_DIR='${RUN_DIR}'
DIP_ARTIFACT_DIR='${STUB_ARTIFACT_DIR}'
EOF
chmod 600 "${RUN_DIR}/env"
printf '%s' "${RID}" > "${DIP_STATE_ROOT}/.current_rid"

# Stage stub responses for every NodeID a persist script will read. The
# fixture JSON files already validate against the schemas — the stub just
# copies them into the per-node response.md slot.
stage_response() {
  node="$1"
  fixture="$2"
  mkdir -p "${STUB_ARTIFACT_DIR}/${node}"
  cp "${FIXTURES}/${fixture}" "${STUB_ARTIFACT_DIR}/${node}/response.md"
}

stage_response SelectNextIssue   selected_issue_sample.json
stage_response PlanMinimalPRs    plan_sample.json
stage_response SquadPragmatism   verdict_pass.json
stage_response SquadYagni        verdict_pass.json
stage_response SquadTestability  verdict_pass.json
stage_response SquadHolistic     verdict_pass.json
stage_response SquadBlocker      verdict_attest_valid.json
stage_response SquadSynthesizer  synthesis_approved.json

# Run a single persist script under the stub-executor env. Asserts:
#   - stdout begins with the expected marker
#   - stdout does NOT contain `tracker` or `.tracker/runs`
#   - no `persist_*_error.txt` was written
# The DEV_LOOP_RUN_DIR + DEV_LOOP_STATE_ROOT env vars steer the bootstrap
# at our test-side RUN_DIR rather than ~/.cache/dip/dev_loop.
run_persist() {
  script_name="$1"
  expected_marker="$2"
  err_sidecar="$3"

  script_path="${SCRIPTS_DIR}/${script_name}"
  if [ ! -f "${script_path}" ]; then
    fail "missing ${script_name} under ${SCRIPTS_DIR}"
    return
  fi

  out_file="${TMPDIR_T}/${script_name}.out"
  # Run with the env file's keys passed in so the bootstrap resolves
  # without depending on a real .current_rid resolution path. The script
  # is invoked the same way tracker invokes it: `sh -c "$(cat <script>)"`.
  (
    cd "${WORKDIR}"
    DEV_LOOP_STATE_ROOT="${DIP_STATE_ROOT}" \
    DEV_LOOP_RUN_DIR="${RUN_DIR}" \
    XDG_CACHE_HOME="${TMPDIR_T}/cache" \
    HOME="${TMPDIR_T}/home" \
    sh -c "$(cat "${script_path}")"
  ) > "${out_file}" 2>&1 || {
    fail "${script_name} exited non-zero"
    return
  }

  # Marker assertion: each persist script's success marker must appear in
  # stdout. We don't pin position — persist_plan.sh / persist_selected_issue.sh
  # follow the marker with a here-doc, but the marker itself must be present.
  if ! grep -qF "${expected_marker}" "${out_file}"; then
    fail "${script_name} did not emit ${expected_marker}; got: $(cat "${out_file}")"
    return
  fi

  # Contract assertion: the script's own routing-marker emission must not
  # name `tracker` or `.tracker/runs`. We isolate the script-emitted prefix
  # (everything up to and including the marker line) from the post-marker
  # here-doc that several persist scripts use to surface the JSON payload
  # into ctx.last_response — that payload is user/agent content, not
  # script-emitted, and matching against it would couple this guard to
  # fixture phrasing.
  prefix_file="${TMPDIR_T}/${script_name}.prefix"
  awk -v m="${expected_marker}" '
    { print }
    index($0, m) { exit }
  ' "${out_file}" > "${prefix_file}"
  if grep -qE 'tracker|\.tracker/runs' "${prefix_file}"; then
    fail "${script_name} emitted tracker-coupled string before/in its marker line under stub executor:"
    grep -nE 'tracker|\.tracker/runs' "${prefix_file}" >&2 || true
    return
  fi

  # No error sidecar should be written on the happy path. (If one IS
  # written, scan it for the forbidden literal too — that's the surface
  # the porting recipe is most concerned with.)
  if [ -n "${err_sidecar}" ] && [ -s "${RUN_DIR}/${err_sidecar}" ]; then
    fail "${script_name} wrote ${err_sidecar} on happy path: $(cat "${RUN_DIR}/${err_sidecar}")"
    return
  fi
}

run_persist persist_selected_issue.sh       persisted-selected     persist_selected_error.txt
run_persist persist_plan.sh                 persisted-plan         persist_plan_error.txt
run_persist persist_pragmatism_verdict.sh   persisted-pragmatism   persist_pragmatism_error.txt
run_persist persist_yagni_verdict.sh        persisted-yagni        persist_yagni_error.txt
run_persist persist_testability_verdict.sh  persisted-testability  persist_testability_error.txt
run_persist persist_holistic_verdict.sh     persisted-holistic     persist_holistic_error.txt
run_persist persist_blocker_verdict.sh      persisted-blocker      persist_blocker_error.txt
run_persist persist_synthesis.sh            synthesized-approved   persist_synthesis_error.txt

# -------------------------------------------------------------------------
# Section 3 — Failure-path neutrality.
#
# When DIP_ARTIFACT_DIR points at a non-existent directory under the stub
# executor, the persist scripts must still emit persist-failed (not the
# tracker-coupled "no tracker run dir" string that #61 removed). One
# representative script is enough: the static guard
# test_persist_neutral_breadcrumb.sh already covers the literal across all
# 8 scripts; here we verify the runtime path actually trips persist-failed
# without naming tracker.
# -------------------------------------------------------------------------

cat > "${RUN_DIR}/env" <<EOF
GH_REPO='test/test'
BASE_BRANCH='main'
ALLOW_NO_CI='false'
DEV_LOOP_RUN_ID='${RID}'
DEV_LOOP_RUN_DIR='${RUN_DIR}'
DIP_ARTIFACT_DIR='${WORKDIR}/.stub-executor/nonexistent-run'
EOF
chmod 600 "${RUN_DIR}/env"

out_file="${TMPDIR_T}/persist_plan_failure.out"
(
  cd "${WORKDIR}"
  DEV_LOOP_STATE_ROOT="${DIP_STATE_ROOT}" \
  DEV_LOOP_RUN_DIR="${RUN_DIR}" \
  XDG_CACHE_HOME="${TMPDIR_T}/cache" \
  HOME="${TMPDIR_T}/home" \
  sh -c "$(cat "${SCRIPTS_DIR}/persist_plan.sh")"
) > "${out_file}" 2>&1 || {
  fail "persist_plan.sh exited non-zero under failure path (should trip trap and exit 0)"
}

if [ "${rc}" -eq 0 ] && ! grep -qF "persist-failed" "${out_file}"; then
  fail "persist_plan.sh did not emit persist-failed under stub-executor failure path: $(cat "${out_file}")"
fi
if [ "${rc}" -eq 0 ] && grep -qE 'tracker|\.tracker/runs' "${RUN_DIR}/persist_plan_error.txt"; then
  fail "persist_plan_error.txt names tracker on failure path: $(cat "${RUN_DIR}/persist_plan_error.txt")"
fi

if [ "${rc}" -eq 0 ]; then
  printf 'OK: porting-contract smoke clean (8 persist scripts + 2 README load-bearing literals)\n'
fi
exit "${rc}"
