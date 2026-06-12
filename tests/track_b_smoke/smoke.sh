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
trap 'rm -rf "${workdir}"' EXIT

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
# track_b_run_dir fails. Under `set -eu` the bare command substitution would
# exit the script before the EXIT trap had a chance to dump diagnostics — and
# the trap then rm -rf's the workdir, taking tracker.stdout/stderr with it.
# Surface those streams to the operator first.
if ! run_dir=$(track_b_run_dir "${workdir}"); then
  printf 'track_b_run_dir failed under %s\n' "${workdir}" >&2
  printf '=== tracker.stdout ===\n' >&2
  sed 's/^/  /' tracker.stdout >&2 || true
  printf '=== tracker.stderr ===\n' >&2
  sed 's/^/  /' tracker.stderr >&2 || true
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
