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
# `tmp` is the test's mktemp -d root; the cleanup trap reads it. `DIP_ROOT`
# is assigned at Section 2 and mirrors test_helpers.bash's test-side alias
# for DEV_LOOP_STATE_ROOT (script-side).
tmp=""
# shellcheck disable=SC2317  # invoked indirectly via trap
cleanup() {
  # Defense-in-depth: only rm -rf paths under a tmpdir root we recognize, so a
  # future refactor that re-points `tmp` at a non-mktemp path can't escalate.
  case "${tmp}" in
    /tmp/*|"${TMPDIR:-/tmp}"/*) rm -rf "${tmp}" ;;
  esac
}
trap cleanup EXIT INT TERM

# Allocate the test's tmpdir up front so Section 1's awk-window scratch file
# (and every subsequent section's artifacts) live under the same root the
# cleanup trap reaps. Originally allocated lazily at the top of Section 2;
# moved up when Section 1 grew a windowed README scan (#89).
tmp="$(mktemp -d)"

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

# Load-bearing anchor — the sentinel comment that marks the discovery block
# in setup_run.sh AND is referenced by name from the README. This is the
# durable contract anchor: it survives the tracker#323 refactor (which
# collapses the discovery body to a single env-var read) because the block
# delimiter does not depend on the implementation strategy. Pinning this
# guarantees the README's "see this block" pointer stays valid even after
# the literals below get rewritten.
LIT_SENTINEL='--- begin dip-executor discovery (PORTING NOTE) ---'

# Third sentinel — the README heading that opens the porting recipe. Pinning
# this guards the operator-observable failure mode where a refactor moves
# the porting literals into a CHANGELOG entry, a "historical context" stub,
# or any other section: the bare `grep -qF` form would still find the
# literal somewhere in the README, but the porter following the recipe
# would not. The README-side LIT_DISCOVERY and LIT_PREREQ_DOC checks below
# are scoped to the awk window between this heading and the next `### ` so
# a literal that escapes the recipe section trips the lock.
LIT_PORTING_HEADING='### Porting to a different dip executor'

# Load-bearing literal #1 — the discovery-block anchor the porting recipe
# names as the porter's first edit target. Anchor on the trailing closing
# quote so a refactor that appends extra characters mid-line trips the lock.
# Single-quoted intentionally so `$(pwd)` is preserved verbatim for the
# grep target (we are pinning the code string as-written, not its expanded
# form).
# shellcheck disable=SC2016
LIT_DISCOVERY='DIP_ARTIFACT_ROOT="$(pwd)/.tracker/runs"'

# Load-bearing literal #2 — the prereq-tool loop the porting recipe names
# as the porter's second edit target. Anchor on the trailing punctuation
# so a list extension after `timeout` trips the lock — that is the failure
# mode where a porter who reads the README and edits setup_run.sh blindly
# would silently miss a new prereq. The setup_run.sh form ends with
# `timeout; do` (loop opener); the README form ends with `timeout;` (the
# trailing `do` is dropped from the backtick-quoted snippet). In README,
# the literal is reflowed across two markdown lines inside one
# backtick-quoted block, so the README assertion collapses whitespace.
LIT_PREREQ_CODE='for cmd in gh jq git tracker yq timeout; do'
LIT_PREREQ_DOC='for cmd in gh jq git tracker yq timeout;'

# Sentinel comment on the setup_run.sh side: the contract anchor proper.
# `-e` marks the pattern explicitly because the literal begins with `---`,
# which grep would otherwise parse as an option.
if ! grep -qF -e "${LIT_SENTINEL}" "${SETUP_RUN}"; then
  fail "setup_run.sh no longer contains the discovery sentinel comment: ${LIT_SENTINEL}"
fi
# README references the sentinel by name; if either side drops the
# reference the porter's pointer goes stale.
if ! grep -qF -e "${LIT_SENTINEL}" "${README}"; then
  fail "README no longer references the discovery sentinel comment: ${LIT_SENTINEL}"
fi
if ! grep -qF "${LIT_DISCOVERY}" "${SETUP_RUN}"; then
  fail "setup_run.sh no longer contains the porting-recipe discovery literal: ${LIT_DISCOVERY}"
fi
if ! grep -qF "${LIT_PREREQ_CODE}" "${SETUP_RUN}"; then
  fail "setup_run.sh no longer contains the porting-recipe prereq loop literal: ${LIT_PREREQ_CODE}"
fi

# Heading-presence check: the porting recipe must still be its own section.
# If the heading drifts or the section is folded into a sibling, the README
# checks below would silently widen scope to neighboring sections; pin the
# heading directly so a rename trips here with an actionable message.
if ! grep -qF "${LIT_PORTING_HEADING}" "${README}"; then
  fail "README no longer contains the porting-recipe heading: ${LIT_PORTING_HEADING}"
fi

# Extract the porting-recipe window: lines from the porting heading
# (exclusive) up to but not including the next `### ` heading. Both README
# literals MUST appear inside this window — a refactor that moves the
# literal into a CHANGELOG entry, a historical-context stub, or any other
# section trips the lock even though `grep -qF` against the whole README
# would still match. The awk pattern reads the heading verbatim via -v to
# avoid quoting hazards; literal `### ` opens any other H3 (including the
# next sibling, `### Resume contract`) and closes the window.
porting_window="${tmp}/porting_window"
# NOTE: terminator matches any `### ` to bound the porting-recipe window.
# If the recipe is later split into H3 subsections (e.g. `### Discovery`,
# `### Prereqs`), update this test to anchor on the known sibling
# `### Resume contract` instead, or expand the window scope.
awk -v heading="${LIT_PORTING_HEADING}" '
  $0 == heading { in_section = 1; next }
  in_section && /^### / { in_section = 0 }
  in_section { print }
' "${README}" > "${porting_window}"

if [ ! -s "${porting_window}" ]; then
  fail "README porting-recipe window is empty (heading present but no body extracted)"
fi

if ! grep -qF "${LIT_DISCOVERY}" "${porting_window}"; then
  fail "README porting-recipe section no longer quotes the discovery literal: ${LIT_DISCOVERY}"
fi
# README form: collapse any run of whitespace (incl. newlines) inside the
# extracted porting-recipe window to a single space, then look for the
# literal. tr to a single-line stream first; grep -F on the collapsed form.
# This is intentionally resilient to markdown reflow but strict on content
# drift (rename or reorder the tools and the assertion trips), AND scoped to
# the porting-recipe section so a literal that escapes into a CHANGELOG or
# historical stub trips the lock.
if ! tr '\n' ' ' < "${porting_window}" | tr -s ' ' | grep -qF "${LIT_PREREQ_DOC}"; then
  fail "README porting-recipe section no longer quotes the prereq loop literal: ${LIT_PREREQ_DOC}"
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

# Mirror test_helpers.bash's setup_env shape, but with an executor-neutral
# artifact-dir name to make the contract-violation message obvious when the
# assertion below trips. `DIP_ROOT` matches the test_helpers.bash naming
# convention: it's the test-side inspection alias for `DEV_LOOP_STATE_ROOT`
# (script-side) — both point at the same tmpdir-anchored dir.
WORKDIR="${tmp}/workdir"
DIP_ROOT="${tmp}/state"
# Deliberately NOT `.tracker/runs`. A second executor would put its
# per-node responses somewhere else; the directory name here is just a
# stand-in for "any other executor's layout".
STUB_ARTIFACT_DIR="${WORKDIR}/.stub-executor/run-abc123"
RID="t-executor-compat-$$"
RUN_DIR="${DIP_ROOT}/runs/${RID}"

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
printf '%s' "${RID}" > "${DIP_ROOT}/.current_rid"

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
#   - stdout contains the expected marker exactly once (so prefix isolation
#     below cannot be widened by a future here-doc payload echoing the
#     marker text inside it)
#   - the script-emitted prefix (everything through the marker line) does
#     NOT contain `tracker` or `.tracker/runs`
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

  out_file="${tmp}/${script_name}.out"
  # Pass DEV_LOOP_RUN_DIR + DEV_LOOP_STATE_ROOT so the bootstrap can find
  # and source the env file directly, without resolving through a real
  # .current_rid lookup. The script is invoked the same way tracker
  # invokes it: `sh -c "$(cat <script>)"`.
  (
    cd "${WORKDIR}"
    DEV_LOOP_STATE_ROOT="${DIP_ROOT}" \
    DEV_LOOP_RUN_DIR="${RUN_DIR}" \
    XDG_CACHE_HOME="${tmp}/cache" \
    HOME="${tmp}/home" \
    sh -c "$(cat "${script_path}")"
  ) > "${out_file}" 2>&1 || {
    fail "${script_name} exited non-zero"
    return
  }

  # Marker assertion: each persist script's success marker must appear in
  # stdout exactly once. Tracker routes on the FIRST marker via marker_grep;
  # a second occurrence inside the post-marker here-doc would defeat the
  # prefix isolation below (the marker line is the prefix boundary) and
  # widen the tracker-string scan to include user/agent content.
  marker_count=$(grep -cF "${expected_marker}" "${out_file}" || true)
  if [ "${marker_count}" -eq 0 ]; then
    fail "${script_name} did not emit ${expected_marker}; got: $(cat "${out_file}")"
    return
  fi
  if [ "${marker_count}" -ne 1 ]; then
    fail "${script_name} emitted ${expected_marker} ${marker_count} times (expected 1); marker must be unique so prefix isolation holds"
    return
  fi

  # Contract assertion: the script's own routing-marker emission must not
  # name `tracker` or `.tracker/runs`. We isolate the script-emitted prefix
  # (everything up to and including the marker line) from the post-marker
  # here-doc that several persist scripts use to surface the JSON payload
  # into ctx.last_response — that payload is user/agent content, not
  # script-emitted, and matching against it would couple this guard to
  # fixture phrasing.
  prefix_file="${tmp}/${script_name}.prefix"
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

out_file="${tmp}/persist_plan_failure.out"
(
  cd "${WORKDIR}"
  DEV_LOOP_STATE_ROOT="${DIP_ROOT}" \
  DEV_LOOP_RUN_DIR="${RUN_DIR}" \
  XDG_CACHE_HOME="${tmp}/cache" \
  HOME="${tmp}/home" \
  sh -c "$(cat "${SCRIPTS_DIR}/persist_plan.sh")"
) > "${out_file}" 2>&1 || fail "persist_plan.sh exited non-zero under failure path (should trip trap and exit 0)"

# Section 3 assertions run unconditionally. The earlier `rc==0` gate hid
# combined regressions: when a Section-2 assertion tripped, Section 3 was
# silently skipped and a porter saw only half of the diff in one CI run.
# `fail` accumulates without exiting, so listing every failure in one shot
# is strictly more informative.
if ! grep -qF "persist-failed" "${out_file}"; then
  fail "persist_plan.sh did not emit persist-failed under stub-executor failure path: $(cat "${out_file}")"
fi
# Positively assert the sidecar exists before scanning it for forbidden
# literals. Without this, a regression that drops the error-breadcrumb
# entirely would silently pass the `! grep ...` form (rc=2 file-not-found
# collapses into rc=1 no-match). The breadcrumb's documented role is to
# name `DIP_ARTIFACT_DIR` — the actionable knob — so we assert that too.
plan_err="${RUN_DIR}/persist_plan_error.txt"
if [ ! -s "${plan_err}" ]; then
  fail "persist_plan.sh failure path did not write persist_plan_error.txt under ${RUN_DIR}"
elif ! grep -qF 'DIP_ARTIFACT_DIR' "${plan_err}"; then
  fail "persist_plan_error.txt does not name DIP_ARTIFACT_DIR (the actionable knob): $(cat "${plan_err}")"
elif grep -qE 'tracker|\.tracker/runs' "${plan_err}"; then
  fail "persist_plan_error.txt names tracker on failure path: $(cat "${plan_err}")"
fi

# -------------------------------------------------------------------------
# Section 4 — setup_run.sh end-to-end stub-port run-through (#88 Gap 1).
#
# Apply the README porting recipe's two edits to a copy of setup_run.sh
# (replace the discovery block with a single-line stub assignment; drop
# `tracker` from the prereq loop), then invoke the patched script against a
# stub-executor layout that has NO .tracker/runs anywhere on disk. Asserts:
#
#   - The patched script emits `setup-ok` (the full bootstrap path works
#     against a non-tracker layout when the porter follows the recipe).
#   - The env file's DIP_ARTIFACT_DIR resolves to the stub path verbatim
#     (the porter's stub assignment survives emit_env's single-quoting and
#     atomic mv; this is the contract the persist scripts then consume).
#   - No `command -v tracker` reference survives downstream of the prereq
#     loop in the patched script — a stale check would silently couple the
#     ported script to tracker again after the porter "finished".
#   - The env file is well-formed: every key in setup_run.sh's emit allow-
#     list (mirrored in test_helpers.bash) is present, single-quoted, and
#     the file sources cleanly under POSIX `set -a; . env; set +a`.
#   - Per-run state survives: rid.txt + started_at.txt + .current_rid line
#     up (downstream cleanup/ratchet rely on this invariant).
#
# This is the runtime side of the porting recipe. Section 1 pins the
# literals statically; without this section, a porter who follows the recipe
# and silently breaks the discovery block (copy-paste error, stale tracker
# reference, missing env var) gets a green test and a bug at first invocation.
# -------------------------------------------------------------------------

S4_DIR="${tmp}/s4"
mkdir -p "${S4_DIR}"
S4_WORKDIR="${S4_DIR}/workdir"
S4_STATE="${S4_DIR}/state"
S4_STUB_ARTIFACT_DIR="${S4_DIR}/stub-exec/run-xyz789"
mkdir -p "${S4_WORKDIR}" "${S4_STATE}/runs" "${S4_STUB_ARTIFACT_DIR}"

# setup_run.sh cd's to git top-level on entry — give WORKDIR a minimal git
# identity so the cd resolves. Suppress any global git template hooks.
( cd "${S4_WORKDIR}" && git init -q -b main . ) 2>/dev/null

# Patch the discovery block to a single stub-assignment line, and drop
# `tracker` from the prereq loop. The block delimiters are pinned by
# Section 1's sentinel lock, so awk's anchor strings cannot drift without
# tripping the static guard first.
PATCHED="${S4_DIR}/setup_run.patched.sh"
awk '
  /--- begin dip-executor discovery \(PORTING NOTE\) ---/ {
    # The porter''s replacement: a single-line read of an executor-published
    # env var. The exact form here mirrors what tracker#323 + future
    # executors are expected to emit.
    print "dip_artifact_dir=\"${STUB_ARTIFACT_DIR}\""
    in_block = 1
    next
  }
  /--- end dip-executor discovery ---/ {
    in_block = 0
    next
  }
  !in_block { print }
' "${SETUP_RUN}" > "${PATCHED}"

# Drop tracker from the prereq loop. The literal is pinned by Section 1's
# LIT_PREREQ_CODE; a drift trips that lock first, so the sed pattern here is
# safe to harden.
sed -i 's/for cmd in gh jq git tracker yq timeout/for cmd in gh jq git yq timeout/' "${PATCHED}"

# Sanity: confirm patch landed (defense against awk/sed silently no-op'ing
# in some weird locale). If these trip, the test is broken, not the porter.
if grep -qF -e "${LIT_SENTINEL}" "${PATCHED}"; then
  fail "Section 4 patcher failed to strip discovery block from setup_run.sh"
fi
if grep -qF 'for cmd in gh jq git tracker yq timeout' "${PATCHED}"; then
  fail "Section 4 patcher failed to drop tracker from prereq loop"
fi
# shellcheck disable=SC2016  # grepping for the literal as-written in the patch
if ! grep -qF 'dip_artifact_dir="${STUB_ARTIFACT_DIR}"' "${PATCHED}"; then
  fail "Section 4 patcher failed to insert stub assignment"
fi

# Downstream-tracker-reference scan: after the prereq loop closes, the
# patched script must not reference `tracker` anywhere — not in `command -v`,
# not in a path, not in a comment that a porter might mistake for live code.
# Comments are stripped first so the contract's documentation references
# (e.g., "tracker#323") in the discovery block's preamble — which the patch
# strips anyway — don't false-positive future maintenance.
#
# `awk` extracts everything after the prereq loop's closing `done` line, and
# `grep -v '^[[:space:]]*#'` drops comment-only lines. The remaining body
# (code + trailing comments on code lines) must be tracker-free.
post_prereq="${S4_DIR}/post_prereq.body"
awk '
  /for cmd in gh jq git yq timeout; do/ { in_loop = 1; next }
  in_loop && /^done$/ { in_loop = 0; emit = 1; next }
  emit { print }
' "${PATCHED}" | grep -v '^[[:space:]]*#' > "${post_prereq}" || true
# Use `grep -nwF`: fixed-string + word-boundary. `\b` in `grep -E` is a GNU
# extension (POSIX ERE treats `\b` as backspace), so the original `\btracker\b`
# would no-op on a BSD/POSIX grep and silently mask a real regression. `-w`
# is portable across GNU/BSD greps and gives us the boundary semantics we want
# (won't match `mytracker`, `tracker_foo`, etc.).
if grep -nwF 'tracker' "${post_prereq}"; then
  fail "patched setup_run.sh still references tracker downstream of prereq loop (see lines above)"
fi

# Invoke the patched script. Bypass gh/network dependencies by exporting
# GH_REPO + DEV_LOOP_BASE_BRANCH so the resolver short-circuits to env src.
s4_out="${S4_DIR}/setup_run.out"
(
  cd "${S4_WORKDIR}"
  STUB_ARTIFACT_DIR="${S4_STUB_ARTIFACT_DIR}" \
  DEV_LOOP_STATE_ROOT="${S4_STATE}" \
  GH_REPO="stub-org/stub-repo" \
  DEV_LOOP_BASE_BRANCH="main" \
  DEV_LOOP_ALLOW_NO_CI="false" \
  XDG_CACHE_HOME="${S4_DIR}/cache" \
  HOME="${S4_DIR}/home" \
  sh -c "$(cat "${PATCHED}")"
) > "${s4_out}" 2>&1 || fail "patched setup_run.sh exited non-zero: $(cat "${s4_out}")"

# Marker assertion: setup-ok is the only acceptable outcome under the
# stub-port. setup-failed / setup-resume-required / setup-lock-held all
# indicate the porter's recipe is broken.
#
# Use `grep -cF` against the marker rather than equality against full stdout —
# a future setup_run.sh that adds a debug line, warning, or trailing
# diagnostic would break the equality form, but the marker contract only
# requires the marker line to appear exactly once (tracker routes on first
# match via marker_grep). Also reject the failure markers explicitly so a
# regression that emits `setup-ok` AND `setup-failed` together (e.g., a
# botched trap) trips here instead of silently passing on the prefix.
s4_ok_count=$(grep -cFx "setup-ok" "${s4_out}" 2>/dev/null || true)
s4_fail_seen=$(grep -cE '^(setup-failed|setup-resume-required|setup-lock-held)$' "${s4_out}" 2>/dev/null || true)
if [ "${s4_ok_count}" != "1" ] || [ "${s4_fail_seen}" != "0" ]; then
  fail "patched setup_run.sh did not emit exactly one setup-ok marker (ok=${s4_ok_count}, failure-markers=${s4_fail_seen}); stdout:"
  cat "${s4_out}" >&2 || true
  s4_rid_for_err=$(cat "${S4_STATE}/.current_rid" 2>/dev/null || true)
  if [ -n "${s4_rid_for_err}" ] && [ -f "${S4_STATE}/runs/${s4_rid_for_err}/setup_error.txt" ]; then
    cat "${S4_STATE}/runs/${s4_rid_for_err}/setup_error.txt" >&2 || true
  fi
fi

# .current_rid + RUN_DIR layout invariants.
s4_rid=$(cat "${S4_STATE}/.current_rid" 2>/dev/null || true)
if [ -z "${s4_rid}" ]; then
  fail "patched setup_run.sh did not publish .current_rid"
else
  s4_run_dir="${S4_STATE}/runs/${s4_rid}"
  if [ ! -f "${s4_run_dir}/env" ]; then
    fail "patched setup_run.sh did not write ${s4_run_dir}/env"
  fi
  if [ ! -f "${s4_run_dir}/rid.txt" ]; then
    fail "patched setup_run.sh did not write rid.txt"
  fi
  if [ ! -f "${s4_run_dir}/started_at.txt" ]; then
    fail "patched setup_run.sh did not write started_at.txt"
  fi

  # Env file content assertions. DIP_ARTIFACT_DIR is the contract surface for
  # downstream persist scripts; if the porter's stub assignment doesn't land
  # here verbatim, every persist script will fail downstream.
  s4_env="${s4_run_dir}/env"
  if [ -f "${s4_env}" ]; then
    expected_line="DIP_ARTIFACT_DIR='${S4_STUB_ARTIFACT_DIR}'"
    if ! grep -qF "${expected_line}" "${s4_env}"; then
      fail "env file does not pin DIP_ARTIFACT_DIR to stub path; got:"
      grep DIP_ARTIFACT_DIR "${s4_env}" >&2 || true
    fi
    # Allow-list completeness — mirrors the comment block above emit_env in
    # setup_run.sh AND test_helpers.bash's unset list. A drift in any of the
    # three trips this assertion. Each key must be emitted in single-quoted
    # form (matches emit_env's `printf "'%s'\n"` shape); the docstring above
    # promises this, so assert it directly instead of trusting one key
    # (DIP_ARTIFACT_DIR's exact-line match below) to stand in for the rest.
    for key in GH_REPO BASE_BRANCH ALLOW_NO_CI DEV_LOOP_RUN_ID \
               DEV_LOOP_RUN_DIR DIP_ARTIFACT_DIR DEV_LOOP_REPO_ROOT; do
      if ! grep -q "^${key}=" "${s4_env}"; then
        fail "env file missing allow-listed key: ${key}"
      fi
      # Single-quote shape: line starts with `KEY='` and ends with `'`.
      # Tolerates emit_env's `'\''` escape for embedded apostrophes (the
      # outer pair still bookends the line). A future emit_env that drops
      # quoting (bare `KEY=value`) or double-quotes trips here.
      if ! grep -qE "^${key}='.*'\$" "${s4_env}"; then
        fail "env file key ${key} is not single-quoted as emit_env promises; got:"
        grep "^${key}=" "${s4_env}" >&2 || true
      fi
    done
    # Well-formedness: the file must source cleanly under POSIX `set -a`.
    # `sh -c` in a fresh subshell so a syntax error doesn't poison this one.
    if ! ( sh -c "set -eu; set -a; . '${s4_env}'; set +a" ) 2>/dev/null; then
      fail "env file is not sourceable under POSIX set -a:"
      cat "${s4_env}" >&2 || true
    fi
  fi
fi

if [ "${rc}" -eq 0 ]; then
  printf 'OK: porting-contract smoke clean (8 persist scripts + README load-bearing literals + sentinel anchor + setup_run stub-port runtime)\n'
fi
exit "${rc}"
