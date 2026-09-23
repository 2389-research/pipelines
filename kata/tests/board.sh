#!/bin/sh
# ABOUTME: Drives the real board.dip looping subgraph under real Tracker, proving per-node streaming, the
# ABOUTME: sweep loop, the morning-review gate, and the empirically pinned max_restarts semantics.
set -eu

pipeline_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
# The real graph and every real script the board runs; the fixture only stands in for the kata CLI and the
# worker. A missing one means the board is half-wired, so fail loudly before the first Tracker run.
for required in board.dip board-report \
  scripts/board-lib.sh scripts/board-preflight.sh scripts/board-record.sh \
  scripts/claim-next.sh scripts/close-selected.sh scripts/handoff-selected.sh; do
  [ -f "$pipeline_dir/$required" ] || {
    printf 'FAIL: %s is missing\n' "$required" >&2
    exit 1
  }
done

test_root=$(mktemp -d)
test_root=$(cd "$test_root" && pwd -P)
trap 'rm -rf "$test_root"' EXIT
trap 'exit 130' HUP INT TERM
KATA_ISOLATE_ROOT="$test_root/isolate"
export KATA_ISOLATE_ROOT
# shellcheck source=/dev/null
. "$pipeline_dir/tests/isolate.sh"
mkdir -p "$test_root/bin" "$test_root/workflow/scripts"

# The kata CLI fixture: a strict stand-in for the eight commands the real board scripts call, backed by
# JSON files under $workspace/.tracker/board-fixture. It never reaches a real Kata daemon.
cat >"$test_root/bin/kata" <<'SH'
#!/bin/sh
# ABOUTME: Fixture Kata CLI: serves ready/list/claim/show/close/label/comment from disposable JSON files.
# ABOUTME: Rejects any unexpected command or flag so no real Kata daemon can ever be contacted.
set -eu
verb=$1
shift
sub=
if [ "$verb" = label ]; then
  sub=$1
  shift
fi
workspace= actor= bodyfile= statusf= unownedf=0
posn=
while [ "$#" -gt 0 ]; do
  case "$1" in
    --workspace) workspace=$2; shift 2 ;;
    --as) actor=$2; shift 2 ;;
    --body-file) bodyfile=$2; shift 2 ;;
    --status) statusf=$2; shift 2 ;;
    --limit) shift 2 ;;
    --message|--commit|--test) shift 2 ;;
    --unowned) unownedf=1; shift ;;
    --if-unowned|--done|--json|--agent) shift ;;
    --*) printf 'unexpected fixture kata flag: %s\n' "$1" >&2; exit 90 ;;
    *) posn="${posn:+$posn }$1"; shift ;;
  esac
done
[ -n "$workspace" ] || { printf 'fixture kata: no --workspace\n' >&2; exit 91; }
fixture="$workspace/.tracker/board-fixture"
katas="$fixture/katas"
printf '%s%s %s\n' "$verb" "${sub:+ $sub}" "$posn" >>"$fixture/kata.log"
# shellcheck disable=SC2086
set -- $posn
kf="$katas/${1:-}.json"
need_kata() { [ -f "$kf" ] || { printf 'fixture kata: no such kata %s\n' "${1:-}" >&2; exit 92; }; }
save() { mv "$kf.tmp" "$kf"; }
case "$verb" in
  ready)
    : >"$fixture/.stream"
    while IFS= read -r u; do
      [ -n "$u" ] || continue
      f="$katas/$u.json"
      [ -f "$f" ] || continue
      if [ "$unownedf" = 1 ]; then
        jq -e '.status == "open" and .owner == null' "$f" >/dev/null || continue
      else
        jq -e '.status == "open"' "$f" >/dev/null || continue
      fi
      cat "$f" >>"$fixture/.stream"
    done <"$fixture/order"
    jq -s '{issues: .}' "$fixture/.stream"
    ;;
  list)
    [ "$statusf" = open ] || { printf 'fixture kata list: unexpected --status %s\n' "$statusf" >&2; exit 93; }
    : >"$fixture/.stream"
    while IFS= read -r u; do
      [ -n "$u" ] || continue
      f="$katas/$u.json"
      [ -f "$f" ] || continue
      jq -e '.status == "open"' "$f" >/dev/null || continue
      cat "$f" >>"$fixture/.stream"
    done <"$fixture/order"
    jq -s '{issues: .}' "$fixture/.stream"
    ;;
  claim)
    need_kata "$1"
    owner=$(jq -r '.owner // ""' "$kf")
    [ -z "$owner" ] || [ "$owner" = "$actor" ] || {
      printf 'fixture kata: %s already owned by %s\n' "$1" "$owner" >&2
      exit 1
    }
    jq --arg a "$actor" '.owner = $a' "$kf" >"$kf.tmp" && save
    jq '{issue: .}' "$kf"
    ;;
  show)
    need_kata "$1"
    jq '{issue: {uid, status, owner, labels}}' "$kf"
    ;;
  close)
    need_kata "$1"
    jq '.status = "closed"' "$kf" >"$kf.tmp" && save
    jq '{issue: .}' "$kf"
    ;;
  label)
    need_kata "$1"
    case "$sub" in
      add) jq --arg l "$2" '.labels = ((.labels // []) + [$l] | unique)' "$kf" >"$kf.tmp" && save ;;
      rm)  jq --arg l "$2" '.labels = ((.labels // []) - [$l])' "$kf" >"$kf.tmp" && save ;;
      *) printf 'unexpected fixture kata label action: %s\n' "$sub" >&2; exit 95 ;;
    esac
    ;;
  comment)
    need_kata "$1"
    [ -n "$bodyfile" ] && cp "$bodyfile" "$fixture/$1.comment"
    ;;
  *) printf 'unexpected fixture kata command: %s\n' "$verb" >&2; exit 94 ;;
esac
SH
chmod +x "$test_root/bin/kata"
export PATH="$test_root/bin:$PATH"

workflow="$test_root/workflow"
# The real graph and real scripts, so the test proves the shipped board, not a copy that can drift.
cp "$pipeline_dir/board.dip" "$workflow/board.dip"
cp "$pipeline_dir/board-report" "$workflow/board-report"
for s in board-lib.sh board-preflight.sh board-record.sh claim-next.sh close-selected.sh handoff-selected.sh; do
  cp "$pipeline_dir/scripts/$s" "$workflow/scripts/$s"
done

# The subgraph body: complete.dip's shape trimmed to the shell nodes, keeping the two crash-safety fail
# edges the board depends on (a failed claim or handoff still reaches Exit so RecordOutcome reads the sweep).
cat >"$workflow/board-item.dip" <<'DIP'
# ABOUTME: Board body fixture: real claim/close/handoff scripts around a fixture worker, with the same
# ABOUTME: crash-safety fail edges as board-item.dip so a failed claim or handoff still reaches Exit.
workflow CompleteKataItem
  goal: "Claim the next ready unowned kata and complete only that item."
  start: ClaimNext
  exit: Exit

  defaults
    fidelity: summary:high

  tool ClaimNext
    label: "Guard workspace and claim one kata"
    marker_grep: "^(claim-ok|queue-empty)"
    timeout: 5m
    command:
      sh "${graph.workflow_dir}/scripts/claim-next.sh"

  tool Implement
    label: "Implement the selected kata"
    timeout: 5m
    command:
      sh "${graph.workflow_dir}/scripts/implement.sh"

  tool CloseSelected
    label: "Land the approved task and close the kata"
    marker_grep: "^close-ok$"
    timeout: 5m
    command:
      sh "${graph.workflow_dir}/scripts/close-selected.sh"

  tool Handoff
    label: "Leave failed work open for review"
    timeout: 5m
    command:
      sh "${graph.workflow_dir}/scripts/handoff-selected.sh"

  tool Exit
    label: "One-item run complete"
    timeout: 5s
    command:
      true

  edges
    ClaimNext -> Implement  on claim-ok
    ClaimNext -> Exit  on queue-empty
    ClaimNext -> Exit  when ctx.outcome = fail
    Implement -> CloseSelected  when ctx.outcome = success
    Implement -> Handoff  when ctx.outcome = fail
    CloseSelected -> Exit  when ctx.outcome = success
    CloseSelected -> Handoff  when ctx.outcome = fail
    Handoff -> Exit  when ctx.outcome = fail
    Handoff -> Exit
DIP

# The fixture worker: a landing commits real work and writes the artifacts close-selected.sh checks; a
# failure (implement-fails present) leaves a dirty file and exits nonzero so the body routes to Handoff.
cat >"$workflow/scripts/implement.sh" <<'SH'
#!/bin/sh
# ABOUTME: Fixture board worker: commits the task and writes verification/completion/approval artifacts,
# ABOUTME: or leaves a dirty tree and fails when $fixture/implement-fails exists so the body hands off.
set -eu
workspace=$(cd "$TRACKER_WORKDIR" && pwd -P)
cd "$workspace"
fixture="$workspace/.tracker/board-fixture"
short=$(jq -er '.short_id' selected.json)
if [ -f "$fixture/implement-fails" ]; then
  printf 'partial work for %s\n' "$short" >"wip-$short.txt"
  printf 'fixture worker could not finish %s\n' "$short" >&2
  exit 34
fi
printf 'implemented %s\n' "$short" >"kata-$short.txt"
git add "kata-$short.txt"
git commit -qm "test: implement $short"
head=$(git rev-parse HEAD)
printf 'fixture tests pass for %s\n' "$short" >verification.txt
printf 'Finished the fixture kata %s with a completion note long enough to clear the sixty character floor.\n' "$short" >completion.md
printf '%s\n' "$head" >review-correctness.approved
printf '%s\n' "$head" >review-scope.approved
SH

# --- helpers -----------------------------------------------------------------

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  if [ -n "${2:-}" ] && [ -f "$2" ]; then
    printf '%s\n' "last 40 log lines ($2):" >&2
    tail -40 "$2" >&2
  fi
  exit 1
}

# Parent --no-tui --json events: newline-delimited clean JSON among non-JSON banner/summary lines. Strip
# any leading non-{ text, parse, keep pipeline events, re-emit compact so the assertions below can slurp.
pev() { jq -Rr 'sub("^[^{]*"; "") as $j | ($j | fromjson? | select(.source == "pipeline")) | tojson' "$1" 2>/dev/null; }
terminal() { pev "$1" | jq -rs '[.[] | select(.type == "pipeline_completed" or .type == "pipeline_failed")][0] | "\(.type) \(.terminal_status // "")"'; }
parent_run() { pev "$1" | jq -rs '[.[] | select(.type == "pipeline_started")][0].run_id // empty'; }
gate_count() { pev "$1" | jq -rs '[.[] | select(.type == "gate_opened")] | length'; }
gate_responses() { pev "$1" | jq -rs '[.[] | select(.type == "gate_resolved") | .gate_response // empty] | join(",")'; }
gate_prompt() { pev "$1" | jq -rs '[.[] | select(.type == "gate_opened")][0].gate_prompt // ""'; }
# shellcheck disable=SC2016
streamed() { [ "$(pev "$1" | jq -rs --arg n "$2" '[.[] | select(.type == "stage_started" and .node_id == $n)] | length > 0')" = true ]; }

ledger_of() { printf '%s/.tracker/runs/%s/board/state.json' "$repo" "$(parent_run "$1")"; }
kinds() { jq -r '[.runs[].kind] | join(",")' "$1"; }
kfile() { printf '%s/katas/01ARZ3NDEKTSV4RRFFQ69G5F%s.json' "$fixture" "$1"; }

# A ready unowned kata: a 26-char Crockford base32 uid (24 fixed + a 2-char suffix) and a lowercase short id.
add_kata() {
  uid="01ARZ3NDEKTSV4RRFFQ69G5F$2"
  jq -n --arg uid "$uid" --arg s "$1" \
    '{uid: $uid, short_id: $s, qualified_id: ("fixture#" + $s), status: "open", owner: null, priority: null, labels: [], child_counts: {open: 0, total: 0}}' \
    >"$fixture/katas/$uid.json"
  printf '%s\n' "$uid" >>"$fixture/order"
}

new_case() {
  case_name=$1
  repo="$test_root/$case_name"
  rm -rf "$repo"
  git init -q -b main "$repo" >/dev/null
  repo=$(cd "$repo" && pwd -P)
  printf 'seed\n' >"$repo/README"
  git -C "$repo" add README
  git -C "$repo" commit -qm 'test: seed board repository'
  fixture="$repo/.tracker/board-fixture"
  mkdir -p "$fixture/katas"
  : >"$fixture/order"
  : >"$fixture/kata.log"
}

# Real Tracker over the real board.dip; extra args (--auto-approve) slot in before the graph. --git off so
# Tracker does not snapshot the disposable repo; --no-tui so a closed stdin is EOF, not a killed controller.
board_run() { tracker --git off --workdir "$repo" --json --no-tui "$@" "$workflow/board.dip"; }

# --- nested-clean: one kata lands, the queue empties, the board reports clean with no gate ---------------
new_case nested-clean
add_kata itemone A0
log="$test_root/nested-clean.log"
rc=0
board_run >"$log" 2>&1 </dev/null || rc=$?
[ "$rc" -eq 0 ] || fail "nested-clean: board exited $rc" "$log"
[ "$(terminal "$log")" = "pipeline_completed success" ] || fail "nested-clean: terminal '$(terminal "$log")'" "$log"
ledger=$(ledger_of "$log")
[ -f "$ledger" ] || fail "nested-clean: ledger missing at $ledger" "$log"
[ "$(kinds "$ledger")" = "completed,empty" ] || fail "nested-clean: ledger kinds '$(kinds "$ledger")'" "$log"
jq -e '.finished == true and .stop_reason == null' "$ledger" >/dev/null || fail "nested-clean: ledger not finished-clean" "$log"
[ "$(gate_count "$log")" = "0" ] || fail "nested-clean: a morning review opened on a clean board" "$log"
# The whole point of the rewrite: each body step streams to the parent console as RunKata/<Node>.
for child in ClaimNext Implement CloseSelected Exit; do
  streamed "$log" "RunKata/$child" || fail "nested-clean: RunKata/$child did not stream to the parent console" "$log"
done
[ "$(git -C "$repo" symbolic-ref --short HEAD)" = "main" ] || fail "nested-clean: not on the trunk after landing" "$log"
[ "$(git -C "$repo" rev-list --count HEAD)" = "2" ] || fail "nested-clean: expected the landing commit on the trunk" "$log"
[ -z "$(git -C "$repo" for-each-ref --format='%(refname:short)' 'refs/heads/kata/*')" ] || fail "nested-clean: a task branch survived the landing" "$log"
[ "$(jq -r '.status' "$(kfile A0)")" = "closed" ] || fail "nested-clean: the kata was not closed in the fixture" "$log"

# --- nested-handoff: a failed worker hands off, the next sweep empties, one gate answered Done -----------
new_case nested-handoff
add_kata itemone A0
: >"$fixture/implement-fails"
printf '1\n' >"$test_root/answers"
log="$test_root/nested-handoff.log"
rc=0
board_run >"$log" 2>&1 <"$test_root/answers" || rc=$?
[ "$rc" -eq 0 ] || fail "nested-handoff: board exited $rc" "$log"
[ "$(terminal "$log")" = "pipeline_completed success" ] || fail "nested-handoff: terminal '$(terminal "$log")'" "$log"
ledger=$(ledger_of "$log")
[ "$(kinds "$ledger")" = "failed,empty" ] || fail "nested-handoff: ledger kinds '$(kinds "$ledger")'" "$log"
jq -e '.runs[0].reason == "implement" and .runs[0].label == "needs-review"' "$ledger" >/dev/null || fail "nested-handoff: first run is not a needs-review implement handoff" "$log"
[ "$(gate_count "$log")" = "1" ] || fail "nested-handoff: expected one morning review (got $(gate_count "$log"))" "$log"
[ "$(gate_responses "$log")" = "done" ] || fail "nested-handoff: gate response '$(gate_responses "$log")'" "$log"
gate_prompt "$log" | grep -Fq "Needs review (1)" || fail "nested-handoff: the review did not list the open kata" "$log"
streamed "$log" "RunKata/Handoff" || fail "nested-handoff: RunKata/Handoff did not stream" "$log"
[ "$(jq -r '.status' "$(kfile A0)")" = "open" ] || fail "nested-handoff: the kata should still be open" "$log"
jq -e '(.labels // []) | any(. == "needs-review")' "$(kfile A0)" >/dev/null || fail "nested-handoff: the kata is not labelled needs-review" "$log"

# --- nested-three-failures: three failed katas in a row stop the board for a person ---------------------
new_case nested-three-failures
add_kata itemone A0
add_kata itemtwo A1
add_kata itemthree A2
: >"$fixture/implement-fails"
printf '1\n' >"$test_root/answers"
log="$test_root/nested-three-failures.log"
rc=0
board_run >"$log" 2>&1 <"$test_root/answers" || rc=$?
[ "$rc" -eq 0 ] || fail "nested-three-failures: board exited $rc" "$log"
[ "$(terminal "$log")" = "pipeline_completed success" ] || fail "nested-three-failures: terminal '$(terminal "$log")'" "$log"
ledger=$(ledger_of "$log")
[ "$(kinds "$ledger")" = "failed,failed,failed" ] || fail "nested-three-failures: ledger kinds '$(kinds "$ledger")'" "$log"
jq -e '.stop_reason == "three consecutive failed children"' "$ledger" >/dev/null || fail "nested-three-failures: stop reason '$(jq -r '.stop_reason' "$ledger")'" "$log"
[ "$(gate_count "$log")" = "1" ] || fail "nested-three-failures: expected one morning review" "$log"
[ "$(gate_responses "$log")" = "done" ] || fail "nested-three-failures: gate response '$(gate_responses "$log")'" "$log"
gate_prompt "$log" | grep -Fq "Stop reason: three consecutive failed children" || fail "nested-three-failures: the review did not name the stop reason" "$log"
gate_prompt "$log" | grep -Fq "Needs review (3)" || fail "nested-three-failures: the review did not list all three katas" "$log"

# --- nested-sweep-again: Sweep again twice then Done, three gates over one released kata ----------------
new_case nested-sweep-again
add_kata itemone A0
: >"$fixture/implement-fails"
printf '2\n2\n1\n' >"$test_root/answers"
log="$test_root/nested-sweep-again.log"
rc=0
board_run >"$log" 2>&1 <"$test_root/answers" || rc=$?
[ "$rc" -eq 0 ] || fail "nested-sweep-again: board exited $rc" "$log"
[ "$(terminal "$log")" = "pipeline_completed success" ] || fail "nested-sweep-again: terminal '$(terminal "$log")'" "$log"
ledger=$(ledger_of "$log")
[ "$(kinds "$ledger")" = "failed,empty,empty,empty" ] || fail "nested-sweep-again: ledger kinds '$(kinds "$ledger")'" "$log"
[ "$(gate_count "$log")" = "3" ] || fail "nested-sweep-again: expected three morning reviews (got $(gate_count "$log"))" "$log"
[ "$(gate_responses "$log")" = "sweep,sweep,done" ] || fail "nested-sweep-again: gate responses '$(gate_responses "$log")'" "$log"

# --- nested-gate-eof: no default and a closed stdin fails the run at the morning review -----------------
new_case nested-gate-eof
add_kata itemone A0
: >"$fixture/implement-fails"
log="$test_root/nested-gate-eof.log"
rc=0
board_run >"$log" 2>&1 </dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "nested-gate-eof: board unexpectedly succeeded on a closed stdin" "$log"
case "$(terminal "$log")" in pipeline_failed*) ;; *) fail "nested-gate-eof: terminal '$(terminal "$log")'" "$log" ;; esac
[ "$(gate_count "$log")" = "1" ] || fail "nested-gate-eof: expected the morning review to open before failing" "$log"
grep -qi 'no input' "$log" || fail "nested-gate-eof: the failure did not report a missing answer" "$log"

# --- nested-auto-approve: --auto-approve with no default takes the first choice, Done -------------------
new_case nested-auto-approve
add_kata itemone A0
: >"$fixture/implement-fails"
log="$test_root/nested-auto-approve.log"
rc=0
board_run --auto-approve >"$log" 2>&1 </dev/null || rc=$?
[ "$rc" -eq 0 ] || fail "nested-auto-approve: board exited $rc" "$log"
[ "$(terminal "$log")" = "pipeline_completed success" ] || fail "nested-auto-approve: terminal '$(terminal "$log")'" "$log"
[ "$(gate_responses "$log")" = "done" ] || fail "nested-auto-approve: gate response '$(gate_responses "$log")'" "$log"
ledger=$(ledger_of "$log")
[ "$(kinds "$ledger")" = "failed,empty" ] || fail "nested-auto-approve: ledger kinds '$(kinds "$ledger")'" "$log"

# --- max-restarts: pin what Tracker's per-run restart budget counts, so board.dip's cap is honest -------
# A single node loops forever; with max_restarts:2 it runs three times (one start plus two restarts), then
# the run fails with "max restarts (2) exceeded". decision_restart carries one run-global restart_count, so
# the board's cap bounds total Preflight restarts in a run, whichever restart edge fires.
probe="$test_root/restart-probe"
mkdir -p "$probe/wf"
cat >"$probe/wf/restart-probe.dip" <<'DIP'
# ABOUTME: Restart probe: loops one node to pin what max_restarts counts for the board sweep loop.
# ABOUTME: Not the board graph; it exists only to make board.dip's max_restarts comment verifiable.
workflow RestartProbe
  goal: "Pin what max_restarts counts for the board loop."
  start: Sweep
  exit: Done
  defaults
    max_restarts: 2
  tool Sweep
    label: "Loop once"
    marker_grep: "^(again|stop)$"
    timeout: 10s
    command:
      sh "${graph.workflow_dir}/sweep.sh"
  tool Done
    label: "Loop finished"
    timeout: 5s
    command:
      true
  edges
    Sweep -> Done  on stop
    Sweep -> Sweep  on again  restart: true
    Sweep -> Done
DIP
cat >"$probe/wf/sweep.sh" <<'SH'
#!/bin/sh
set -eu
c="$TRACKER_WORKDIR/sweeps"
n=$(cat "$c" 2>/dev/null || echo 0)
n=$((n + 1))
printf '%s\n' "$n" >"$c"
printf 'again\n'
SH
rm -rf "$probe/repo"
git init -q -b main "$probe/repo" >/dev/null
probe_repo=$(cd "$probe/repo" && pwd -P)
git -C "$probe_repo" commit -q --allow-empty -m 'test: seed restart probe'
log="$test_root/max-restarts.log"
rc=0
tracker --git off --workdir "$probe_repo" --json --no-tui "$probe/wf/restart-probe.dip" >"$log" 2>&1 </dev/null || rc=$?
[ "$rc" -ne 0 ] || fail "max-restarts: the probe was expected to exhaust its restarts" "$log"
[ "$(cat "$probe_repo/sweeps")" = "3" ] || fail "max-restarts: loop ran $(cat "$probe_repo/sweeps") times, expected 3 (start plus max_restarts=2)" "$log"
case "$(terminal "$log")" in pipeline_failed*) ;; *) fail "max-restarts: terminal '$(terminal "$log")'" "$log" ;; esac
pev "$log" | jq -rs '[.[] | select(.type == "pipeline_failed")][0].message' | grep -Fq 'max restarts (2) exceeded' || fail "max-restarts: failure message did not report the cap" "$log"

printf 'board: ok\n'
