#!/usr/bin/env bats
# ABOUTME: Bats tests for smoke.sh's workdir lifecycle. Uses a PATH shim to
# ABOUTME: stand in for `tracker`, so these tests run without any LLM calls.
# ABOUTME: Focused on the cleanup-on-failure contract: a failing assertion
# ABOUTME: must leave the temp workdir behind for operator inspection.

setup() {
  SMOKE="${BATS_TEST_DIRNAME}/smoke.sh"
  TMPDIR="$(mktemp -d -t track_b_smoke_test.XXXXXX)"
  export TMPDIR
  SHIM="${TMPDIR}/bin"
  mkdir -p "${SHIM}"
  export PATH="${SHIM}:${PATH}"
  # Smoke harness creates its own workdir under the system temp dir; capture
  # the tree before/after so we can identify the workdir it produced.
  SYS_TMP=$(dirname "$(mktemp -u -t track_b_smoke.XXXXXX)")
  export SYS_TMP
}

teardown() {
  # Best-effort cleanup of any smoke harness workdirs left behind on failure.
  find "${SYS_TMP}" -maxdepth 1 -name 'track_b_smoke.*' -type d -mmin -5 \
    -exec rm -rf {} + 2>/dev/null || true
  rm -rf "${TMPDIR}"
}

# write_tracker_shim <body> -- emit a fake `tracker` on PATH whose body runs
# inside the workdir smoke.sh cd'd into.
write_tracker_shim() {
  cat > "${SHIM}/tracker" <<EOF
#!/bin/sh
${1}
EOF
  chmod +x "${SHIM}/tracker"
}

# latest_smoke_workdir -- echo the most recently created track_b_smoke.* dir.
latest_smoke_workdir() {
  find "${SYS_TMP}" -maxdepth 1 -name 'track_b_smoke.*' -type d -mmin -5 \
    -printf '%T@ %p\n' 2>/dev/null \
    | sort -nr | head -1 | awk '{print $2}'
}

@test "smoke.sh removes workdir on success" {
  # Fake tracker emits a clean activity.jsonl + response.md — all assertions pass.
  write_tracker_shim '
mkdir -p ./.tracker/runs/r1/Exit
printf "agent text without tool calls\n" > ./.tracker/runs/r1/Exit/response.md
printf "%s\n" "{\"type\":\"stage_started\",\"node_id\":\"Exit\"}" \
  > ./.tracker/runs/r1/activity.jsonl
exit 0
'
  run "${SMOKE}" verify
  [ "${status}" -eq 0 ]
  # The smoke harness should have removed its workdir on success. Probe the
  # system temp dir for any track_b_smoke.* tree younger than this test —
  # there should be none.
  wd=$(latest_smoke_workdir)
  [ -z "${wd}" ]
}

@test "smoke.sh preserves workdir on assertion failure" {
  # Fake tracker emits an activity.jsonl with a tool_call_start event — the
  # no-tool-events assertion must fail.
  write_tracker_shim '
mkdir -p ./.tracker/runs/r1/Exit
printf "agent text\n" > ./.tracker/runs/r1/Exit/response.md
{
  printf "%s\n" "{\"type\":\"stage_started\",\"node_id\":\"Exit\"}"
  printf "%s\n" "{\"type\":\"tool_call_start\",\"node_id\":\"Exit\",\"tool\":\"finish\"}"
} > ./.tracker/runs/r1/activity.jsonl
exit 0
'
  run "${SMOKE}" verify
  [ "${status}" -ne 0 ]
  # The workdir must still exist for the operator.
  wd=$(latest_smoke_workdir)
  [ -n "${wd}" ]
  [ -d "${wd}" ]
  # The workdir path should appear in smoke.sh's stderr so the operator
  # knows where to look.
  case "${output}" in
    *"${wd}"*) ;;
    *) printf 'expected workdir path in output: %s\n' "${output}" >&2; return 1 ;;
  esac
  # Tracker stdout/stderr should still be on disk for diagnosis.
  [ -f "${wd}/tracker.stdout" ]
  [ -f "${wd}/tracker.stderr" ]
  # Clean it up explicitly so the next test starts fresh.
  rm -rf "${wd}"
}

@test "smoke.sh preserves workdir when track_b_run_dir fails" {
  # Fake tracker exits without ever creating .tracker/runs — the run_dir
  # lookup must fail and the workdir must be preserved.
  write_tracker_shim '
printf "tracker shim: no runs dir created\n" >&2
exit 0
'
  run "${SMOKE}" verify
  [ "${status}" -ne 0 ]
  wd=$(latest_smoke_workdir)
  [ -n "${wd}" ]
  [ -d "${wd}" ]
  # tracker.stderr should be retained too.
  [ -f "${wd}/tracker.stderr" ]
  rm -rf "${wd}"
}

@test "TRACK_B_SMOKE_KEEP=1 retains workdir even on success" {
  write_tracker_shim '
mkdir -p ./.tracker/runs/r1/Exit
printf "agent text without tool calls\n" > ./.tracker/runs/r1/Exit/response.md
printf "%s\n" "{\"type\":\"stage_started\",\"node_id\":\"Exit\"}" \
  > ./.tracker/runs/r1/activity.jsonl
exit 0
'
  TRACK_B_SMOKE_KEEP=1 run "${SMOKE}" verify
  [ "${status}" -eq 0 ]
  wd=$(latest_smoke_workdir)
  [ -n "${wd}" ]
  [ -d "${wd}" ]
  rm -rf "${wd}"
}
