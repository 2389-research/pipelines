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

  family  one of: verify | verify-runner | verify-sprint-exec
                 | verify-sprint-runner | verify-greenfield

  verify               — runs sprint/verify_sprint.dip with no seed; expected
                         to fail at Start and route to the converted Exit
                         agent. Cheapest probe (~1 LLM call).
  verify-runner        — runs sprint/verify_sprints_runner.dip with no ledger;
                         same cheap-probe shape.
  verify-sprint-exec   — runs sprint/sprint_exec_yaml_v2.dip with a pre-seeded
                         all-completed ledger; exercises the converted Start
                         and Exit agents via the FindNextSprint=all-done
                         short-circuit. ~2 LLM calls.
  verify-sprint-runner — runs sprint/sprint_runner_yaml_v2.dip with no ledger;
                         exercises the converted Start and Exit agents via
                         the check_ledger=no_ledger short-circuit. ~3 LLM
                         calls (Start, no_ledger_exit, Exit).
  verify-greenfield    — runs greenfield/greenfield_synthesis.dip with no
                         workspace/raw/l1-summary.yaml; exercises the
                         converted Start and Exit agents via the
                         ReadL1Summary=no-l1-summary short-circuit. ~2 LLM
                         calls.

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
#   converted_nodes — space-separated list of node IDs of the `tool_access: none`
#                     agents under test (each gets the full 4-assertion battery)
#   extra_files     — positional-args list of extra files to copy (use `set --`)
#   seed_workdir    — name of a shell function to run inside the workdir after
#                     pipeline copy, to pre-seed any state the probe needs to
#                     short-circuit. Default is a no-op.
seed_workdir() { :; }
case "${family}" in
  verify)
    pipeline="${repo_root}/sprint/verify_sprint.dip"
    # Exit is the converted `tool_access: none` agent in verify_sprint.dip.
    # Without .ai/current_verify_id.txt the Start tool exits 1 and routes to Exit.
    # Start in verify_sprint.dip is NOT a `tool_access: none` agent (it's the
    # tool node that fails to short-circuit), so we only assert on Exit here.
    converted_nodes=Exit
    set --
    ;;
  verify-runner)
    pipeline="${repo_root}/sprint/verify_sprints_runner.dip"
    # Exit is the converted `tool_access: none` agent in verify_sprints_runner.dip.
    # Without .ai/ledger.yaml the FindCompletedSprints tool fails and routes to Exit.
    # Start in verify_sprints_runner.dip is the tool-running entry node, not a
    # converted Cat-B/-C agent, so we only assert on Exit here.
    converted_nodes=Exit
    # verify_sprints_runner.dip references verify_sprint.dip as a subgraph; the
    # tracker loader resolves it relative to the runner's directory, so both
    # files must land side-by-side in the temp workdir.
    set -- "${repo_root}/sprint/verify_sprint.dip"
    ;;
  verify-sprint-exec)
    pipeline="${repo_root}/sprint/sprint_exec_yaml_v2.dip"
    # Exit is one of three converted `tool_access: none` agents in
    # sprint_exec_yaml_v2.dip (Start, Exit, ReviewAnalysis). We pre-seed an
    # all-completed ledger so EnsureLedger skips creation, FindNextSprint
    # reports `all-done`, and the workflow routes Start -> ...tools... -> Exit
    # without ever entering the implementation lane. Exercises both converted
    # Start and Exit agents in one run; we assert on both.
    converted_nodes="Start Exit"
    set --
    seed_workdir() {
      mkdir -p .ai
      cat >.ai/ledger.yaml <<'YAML'
project:
  name: "track-b-smoke-probe"
  stack:
    lang: null
    runner: null
    test: null
    lint: null
    build: null
  created_at: "2026-01-01T00:00:00Z"

sprints:
  - id: "000"
    title: "Probe sprint (already completed)"
    status: completed
    bootstrap: true
    depends_on: []
    complexity: low
    created_at: "2026-01-01T00:00:00Z"
    updated_at: "2026-01-01T00:00:00Z"
    attempts: 0
    total_cost: "0.00"
YAML
    }
    ;;
  verify-sprint-runner)
    pipeline="${repo_root}/sprint/sprint_runner_yaml_v2.dip"
    # Exit is the converted `tool_access: none` agent in sprint_runner_yaml_v2.
    # Without .ai/ledger.yaml the check_ledger tool prints `no_ledger`, routes
    # to no_ledger_exit (a tool-access-allowed agent that reports the missing
    # ledger), then -> Exit (converted). Exercises both converted Start and
    # Exit agents; we assert on both.
    #
    # sprint_runner_yaml_v2.dip declares two subgraphs (execute_sprint ->
    # sprint_exec_yaml_v2.dip, redecompose_sprint -> spec_to_sprints_yaml_v2.dip)
    # which tracker resolves at load time. Both must land in the temp workdir
    # even though the no-ledger path never enters them.
    converted_nodes="Start Exit"
    set -- \
      "${repo_root}/sprint/sprint_exec_yaml_v2.dip" \
      "${repo_root}/sprint/spec_to_sprints_yaml_v2.dip"
    ;;
  verify-greenfield)
    pipeline="${repo_root}/greenfield/greenfield_synthesis.dip"
    # Exit is the converted `tool_access: none` agent in greenfield_synthesis.
    # Without workspace/raw/l1-summary.yaml the ReadL1Summary tool prints
    # `no-l1-summary`, which routes directly to Exit. Exercises both converted
    # Start and Exit agents; we assert on both.
    converted_nodes="Start Exit"
    set --
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

# yq preflight for sprint families. Without yq on PATH, sprint_exec_yaml_v2
# routes CheckYq -> YqMissing -> Exit, and sprint_runner_yaml_v2 routes
# check_yq -> yq_missing -> Exit (the .dip files use different casing for
# the same gating pattern). That's a real short-circuit edge the pipeline
# supports, but it is NOT the converged-end-state path these probes are meant
# to exercise; passing via the yq-missing edge would silently weaken the
# converted-node coverage claim (the wrong Exit, reached via the wrong route).
# Fail fast here instead. verify-greenfield's `ReadL1Summary` short-circuit
# prints `no-l1-summary` *before* invoking yq, so the greenfield probe doesn't
# need yq on PATH.
case "${family}" in
  verify-sprint-exec|verify-sprint-runner)
    if ! command -v yq >/dev/null 2>&1; then
      printf 'setup error: yq not installed; sprint probes require yq\n' >&2
      printf '  install: brew install yq  (macOS) | snap install yq (Linux)\n' >&2
      exit 2
    fi
    ;;
esac

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

# Per-family seed: pre-create any files the probe needs in order to
# short-circuit (e.g. a pre-completed ledger for sprint-exec). Runs in the
# workdir so seed_workdir uses relative paths.
( cd "${workdir}" && seed_workdir )

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

# Run the 4-assertion battery against every converted node listed by the
# family branch. Looping (rather than extracting a helper) preserves the
# copy-paste-per-probe discipline: each assertion still reads as a flat,
# greppable line in the harness, and a single node's failure under set -e
# halts the whole run with the workdir retained.
# shellcheck disable=SC2086
# ^ intentional word-splitting: converted_nodes is a space-separated list.
for converted_node in ${converted_nodes}; do
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
done

printf 'PASS: %s smoke — %s ran without dispatching tools\n' "${family}" "${converted_nodes}"
pass=1
