#!/bin/sh
# ABOUTME: Track B runtime smoke harness — invokes a real tracker pipeline
# ABOUTME: against a converted `tool_access: none` agent and asserts the
# ABOUTME: agent emitted plain text without dispatching tools (issue #19).
# ABOUTME:
# ABOUTME: NOT wired into CI by default — runs cost real money. Operator
# ABOUTME: triggers manually per the README.md table. POSIX sh.
set -eu

usage() {
  cat <<'EOF'
Usage: smoke.sh <family>

  family  one of: verify | verify-runner

  verify         — runs sprint/verify_sprint.dip with no seed; expected to
                   fail at Start and route to the converted Exit agent.
                   Cheapest probe (~1 LLM call on the converted agent only).
  verify-runner  — runs sprint/verify_sprints_runner.dip with no ledger;
                   same cheap-probe shape.

Heavier probes (greenfield / sprint exec / sprint runner) are documented
in README.md but not implemented as auto-runners because they require seed
inputs and run to completion. Operators wire them as needed.

Exit codes
  0   smoke passed — agent ran without dispatching tools
  1   assertion failed — see stderr
  2   misuse / setup error
EOF
}

if [ "$#" -ne 1 ]; then
  usage >&2
  exit 2
fi

family=$1
script_dir=$(cd "$(dirname "$0")" && pwd)
repo_root=$(cd "${script_dir}/../.." && pwd)

# shellcheck disable=SC1091
. "${script_dir}/lib.sh"

# Each branch sets:
#   pipeline        — absolute path to the .dip to copy into the temp workdir
#   converted_node  — node ID of the `tool_access: none` agent under test
#   extra_files     — positional-args list of extra files to copy (use `set --`)
case "${family}" in
  verify)
    pipeline="${repo_root}/sprint/verify_sprint.dip"
    # Exit is the converted `tool_access: none` agent in verify_sprint.dip.
    # Without .ai/current_verify_id.txt the Start tool exits 1 and routes to Exit.
    converted_node=Exit
    set --
    ;;
  verify-runner)
    pipeline="${repo_root}/sprint/verify_sprints_runner.dip"
    # Exit is the converted `tool_access: none` agent in verify_sprints_runner.dip.
    # Without .ai/ledger.yaml the FindCompletedSprints tool fails and routes to Exit.
    converted_node=Exit
    # verify_sprints_runner.dip references verify_sprint.dip as a subgraph; the
    # tracker loader resolves it relative to the runner's directory, so both
    # files must land side-by-side in the temp workdir.
    set -- "${repo_root}/sprint/verify_sprint.dip"
    ;;
  *)
    printf 'unknown family: %s\n' "${family}" >&2
    usage >&2
    exit 2
    ;;
esac

if [ ! -f "${pipeline}" ]; then
  printf 'pipeline not found: %s\n' "${pipeline}" >&2
  exit 2
fi

if ! command -v tracker >/dev/null 2>&1; then
  printf 'tracker not on PATH; install per dev_loop/README.md prerequisites\n' >&2
  exit 2
fi

workdir=$(mktemp -d -t track_b_smoke.XXXXXX)

# Cleanup contract: remove the workdir only when the smoke run passed *and*
# the operator did not opt into retention. On any failure (assertion failure
# under `set -e`, tracker-runs lookup failure, signal) we leave the workdir
# in place so the operator can inspect `.tracker/runs/...`, `tracker.stdout`,
# and `tracker.stderr`. The trap also dumps the tracker streams to stderr so
# the failure message and the diagnostics arrive in the same log block.
pass=0
on_exit() {
  status=$?
  if [ "${pass}" -eq 1 ] && [ "${TRACK_B_SMOKE_KEEP:-0}" != 1 ]; then
    rm -rf "${workdir}"
  else
    printf '\n--- smoke harness retained workdir for inspection ---\n' >&2
    printf 'workdir: %s\n' "${workdir}" >&2
    if [ -f "${workdir}/tracker.stdout" ]; then
      printf '=== tracker.stdout ===\n' >&2
      sed 's/^/  /' "${workdir}/tracker.stdout" >&2 || true
    fi
    if [ -f "${workdir}/tracker.stderr" ]; then
      printf '=== tracker.stderr ===\n' >&2
      sed 's/^/  /' "${workdir}/tracker.stderr" >&2 || true
    fi
  fi
  exit "${status}"
}
trap on_exit EXIT

# Copy the pipeline (and any subgraph deps in "$@") into the temp workdir so
# per-run state lands there and not under the repo's .tracker/. Hermetic by
# design. The positional-args list is the POSIX-clean carrier for zero/one/N
# paths, including ones with whitespace.
cp "${pipeline}" "${workdir}/"
for f in "$@"; do
  cp "${f}" "${workdir}/"
done
pipeline_basename=$(basename "${pipeline}")

# Invoke tracker. --no-tui keeps stdout/stderr readable in CI / logs.
# --auto-approve replaces any human gate with deterministic accept (these
# pipelines don't gate on the converted nodes' paths, but it's defensive).
# Track B pipelines may legitimately exit non-zero (e.g. the verify probe is
# *supposed* to fail at Start) — we capture but do not fail on it.
cd "${workdir}"
tracker_status=0
tracker --no-tui --auto-approve "${pipeline_basename}" >tracker.stdout 2>tracker.stderr \
  || tracker_status=$?
printf 'tracker exit: %s\n' "${tracker_status}" >&2

# If tracker never created a .tracker/runs/ dir (or the dir is empty),
# track_b_run_dir fails. The `if !` guard keeps `set -eu` from terminating
# the script before we set `pass` semantics. The on_exit trap will retain
# the workdir and dump tracker.stdout/stderr so the operator can diagnose.
if ! run_dir=$(track_b_run_dir "${workdir}"); then
  printf 'track_b_run_dir failed under %s\n' "${workdir}" >&2
  exit 1
fi
printf 'run dir: %s\n' "${run_dir}" >&2

# Assertion 1: the converted node was actually exercised. Without this the
# rest pass vacuously when the pipeline shape changed and the node was
# skipped.
track_b_assert_node_reached "${run_dir}" "${converted_node}"

# Assertion 2: a response.md was produced (the converted agent emitted text).
track_b_assert_response_exists "${run_dir}" "${converted_node}"

# Assertion 3: the response.md contains no TOOL CALL transcript markers.
# This is what `tool_access: none` is supposed to guarantee.
track_b_assert_no_tool_calls_in_response "${run_dir}" "${converted_node}"

# Assertion 4: activity.jsonl shows zero tool_call_start events on this node.
# Stricter than the response.md check — catches the case where tracker
# dispatched a tool but the transcript formatting elided it.
track_b_assert_no_tool_events_in_activity "${run_dir}" "${converted_node}"

printf 'PASS: %s smoke — %s ran without dispatching tools\n' "${family}" "${converted_node}"
pass=1
