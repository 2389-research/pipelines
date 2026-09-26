#!/bin/sh
# ABOUTME: Verifies the roborev issue fixer's parsed routes, agent models, and tool-node commands.
# ABOUTME: Proves audited-only commits, prompt-free queue snapshots, and a clear stop without jq.
set -eu

roborev_dir=$(CDPATH='' cd -- "$(dirname "$0")/.." && pwd -P)
workflow="$roborev_dir/roborev_issue_fixer.dip"
test_root=$(mktemp -d)
cleanup() {
  cleanup_status=$1
  if [ "$cleanup_status" -eq 0 ]; then
    rm -rf "$test_root"
  else
    printf 'graph test logs retained at %s\n' "$test_root" >&2
  fi
}
trap 'cleanup $?' EXIT
trap 'exit 130' HUP INT TERM

fail() {
  printf 'graph: %s\n' "$1" >&2
  exit 1
}

# DIP101 and DIP102 are expected: Abort reaches Done only on a fail outcome, so an
# Abort that claims success never reaches the exit as a pass. Any other warning fails;
# hints are skipped because dippin 0.72.0 hints at the `: > file` truncation idiom.
dippin check --format json "$workflow" >"$test_root/check.json" || fail "dippin check failed"
jq -e '
  .valid == true and .errors == 0
  and ([.diagnostics[] | select(.severity != "hint") | .code] | sort) == ["DIP101", "DIP102"]
' "$test_root/check.json" >/dev/null || fail "unexpected dippin diagnostics; see $test_root/check.json"
tracker validate "$workflow" >"$test_root/tracker-validate" 2>&1 || fail "tracker validate failed"

# The per-review counters (option 2) replace the run-wide clock: no code path
# should reintroduce a graph-level max_wall_time.
if grep -q 'max_wall_time' "$workflow"; then
  fail "max_wall_time must not appear in the workflow"
fi

dippin simulate "$workflow" --all-paths >"$test_root/events" 2>"$test_root/paths" ||
  fail "dippin simulate failed"

jq -se '
  [.[] | select(.event == "node_enter" and .kind == "agent")]
  | length > 0
  and all(.provider == "openai-compat" and .model == "deepseek-4.1-flash")
' "$test_root/events" >/dev/null || fail "every agent must run deepseek-4.1-flash via openai-compat"

# Tracker counts a missing STATUS line as success on agents that are not goal gates,
# so PatchAudit's outcome alone must never reach CommitFix.
jq -se '
  [.[] | select(.event == "edge_traverse" and .to == "CommitFix")]
  | length > 0
  and all(.from == "RoutePatchAudit" and .condition == "ctx.tool_marker = approve")
' "$test_root/events" >/dev/null || fail "CommitFix must be reachable only from RoutePatchAudit on approve"

# RepairBudget is the only gate that may hand work to ImplementFix, so every path
# into it -- including re-review failures and no-change loops that loop back
# through RouteTriage's fix edge -- is bounded by the same repair budget.
jq -se '
  [.[] | select(.event == "edge_traverse" and .to == "ImplementFix")]
  | length > 0
  and all(.from == "RepairBudget" and .condition == "ctx.tool_marker = repair")
' "$test_root/events" >/dev/null || fail "ImplementFix must be reachable only from RepairBudget on repair"

jq -se '
  any(.[]; .event == "edge_traverse" and .from == "RepairBudget" and .to == "DeferCurrent" and .condition == "ctx.tool_marker = exhausted")
' "$test_root/events" >/dev/null || fail "RepairBudget must route exhausted to DeferCurrent"

jq -se '
  any(.[]; .event == "edge_traverse" and .from == "QueueContext" and .to == "FinalContext" and .condition == "ctx.tool_marker = review_cap")
' "$test_root/events" >/dev/null || fail "QueueContext must route review_cap to FinalContext"

# extract_command NODE [KEY=VALUE...]: write the tool node's command, dedented, to
# $test_root/NODE.sh. Tracker replaces ${params.KEY} and ${graph.KEY} textually
# before a tool command ever reaches sh, so plain sh cannot parse those raw
# tokens; each KEY=VALUE renders both namespaces' token to VALUE the same way.
extract_command() {
  node=$1
  shift
  awk -v node="$node" '
    $1 == "tool" && $2 == node { found = 1; next }
    found && /^  [^ ]/ { exit }
    found && $1 == "command:" { body = 1; next }
    body { sub(/^      /, ""); print }
  ' "$workflow" >"$test_root/$node.sh"
  [ -s "$test_root/$node.sh" ] || fail "$node has no command"
  for kv in "$@"; do
    key=${kv%%=*}
    value=${kv#*=}
    sed "s/\${params\.$key}/$value/g; s/\${graph\.$key}/$value/g" \
      "$test_root/$node.sh" >"$test_root/$node.sh.tmp"
    mv "$test_root/$node.sh.tmp" "$test_root/$node.sh"
  done
}

# Run the verdict parser exactly as the pipeline writes it against sample audit responses.
extract_command RoutePatchAudit

# expect_verdict WANT RESPONSE: RESPONSE is printf %b text, or "missing" for no response file.
expect_verdict() {
  run_dir="$test_root/run"
  rm -rf "$run_dir"
  mkdir -p "$run_dir/PatchAudit"
  if [ "$2" != missing ]; then
    printf '%b' "$2" >"$run_dir/PatchAudit/response.md"
  fi
  got=$(TRACKER_RUN_DIR="$run_dir" sh "$test_root/RoutePatchAudit.sh")
  [ "$got" = "$1" ] || fail "audit response '$2' gave verdict '$got', want '$1'"
}

expect_verdict approve 'Checks pass.\nAUDIT: approve\nSTATUS: success\n'
expect_verdict approve 'AUDIT: approve   # ready to commit\nSTATUS: success\n'
expect_verdict reject 'The nil path has no test.\nAUDIT: reject\nSTATUS: success\n'
expect_verdict invalid 'Looks fine to me.\nSTATUS: success\n'
expect_verdict invalid 'AUDIT: approved\nSTATUS: success\n'
expect_verdict invalid missing

# A stand-in roborev answers every call with a two-review queue whose job prompts carry a
# marker, the way real list output carries each reviewed diff.
stub_bin="$test_root/bin"
mkdir -p "$stub_bin"
cat >"$test_root/queue.json" <<'EOF'
[
  {"id": 61, "git_ref": "929d219", "branch": "wip/x", "repo_path": "/r", "status": "done",
   "verdict": "F", "enqueued_at": "2026-09-25T10:00:00Z", "prompt": "REVIEW-PROMPT-BODY diff a"},
  {"id": 64, "git_ref": "1d41990", "branch": "wip/x", "repo_path": "/r", "status": "done",
   "verdict": "P", "enqueued_at": "2026-09-25T11:00:00Z", "prompt": "REVIEW-PROMPT-BODY diff b"}
]
EOF
printf '#!/bin/sh\ncat "%s"\n' "$test_root/queue.json" >"$stub_bin/roborev"
chmod +x "$stub_bin/roborev"

# expect_queue_snapshot NODE MARKER SAVED [KEY=VALUE...]: the node keeps the full list
# in roborev/SAVED but prints only per-review selection fields. Forty open reviews
# once put 1.3 MB of job prompts into SelectReview and overflowed DeepSeek's 1M-token
# context. selected-count defaults to 0 (well under any max_reviews used here), so
# the snapshot runs its normal, uncapped path.
expect_queue_snapshot() {
  node=$1
  marker=$2
  saved=$3
  shift 3
  extract_command "$node" "$@"
  run_dir="$test_root/run-$node"
  mkdir -p "$run_dir/roborev"
  printf '0\n' >"$run_dir/roborev/selected-count"
  (cd "$test_root" && PATH="$stub_bin:$PATH" TRACKER_RUN_DIR="$run_dir" sh "$test_root/$node.sh") \
    >"$test_root/$node.out" 2>"$test_root/$node.err" || fail "$node exited nonzero"
  [ "$(tail -n 1 "$test_root/$node.out")" = "$marker" ] || fail "$node did not end with $marker"
  if grep -q REVIEW-PROMPT-BODY "$test_root/$node.out"; then
    fail "$node passed job prompts to the agent"
  fi
  grep -q '"id":61,"git_ref":"929d219"' "$test_root/$node.out" || fail "$node dropped review 61"
  grep -q '"verdict":"P"' "$test_root/$node.out" || fail "$node dropped review 64's verdict"
  grep -q REVIEW-PROMPT-BODY "$run_dir/roborev/$saved" || fail "$node did not keep the full list in $saved"
}

expect_queue_snapshot QueueContext queue_ready open.json max_reviews=30
expect_queue_snapshot FinalContext final_ready final-open.json max_reviews=30

# At the review cap, QueueContext must stop before ever calling roborev.
extract_command QueueContext max_reviews=2
cap_run_dir="$test_root/run-queuecap"
mkdir -p "$cap_run_dir/roborev"
printf '2\n' >"$cap_run_dir/roborev/selected-count"
got=$(cd "$test_root" && PATH="$stub_bin:$PATH" TRACKER_RUN_DIR="$cap_run_dir" sh "$test_root/QueueContext.sh")
[ "$got" = review_cap ] || fail "QueueContext at the cap printed '$got', want review_cap"
[ ! -e "$cap_run_dir/roborev/open.json" ] || fail "QueueContext called roborev after reaching the cap"

# FinalContext reports the review-cap block whether or not the cap was reached.
extract_command FinalContext max_reviews=3
atcap_run_dir="$test_root/run-finalcap"
mkdir -p "$atcap_run_dir/roborev"
printf '3\n' >"$atcap_run_dir/roborev/selected-count"
(cd "$test_root" && PATH="$stub_bin:$PATH" TRACKER_RUN_DIR="$atcap_run_dir" sh "$test_root/FinalContext.sh") \
  >"$test_root/FinalContext-cap.out" 2>"$test_root/FinalContext-cap.err" ||
  fail "FinalContext at the cap exited nonzero"
grep -q '^selected: 3$' "$test_root/FinalContext-cap.out" || fail "FinalContext did not report selected at the cap"
grep -q '^max_reviews: 3$' "$test_root/FinalContext-cap.out" || fail "FinalContext did not report max_reviews at the cap"
grep -q '^cap_reached: yes$' "$test_root/FinalContext-cap.out" || fail "FinalContext did not mark cap_reached yes at the cap"

extract_command FinalContext max_reviews=30
belowcap_run_dir="$test_root/run-finalbelowcap"
mkdir -p "$belowcap_run_dir/roborev"
printf '5\n' >"$belowcap_run_dir/roborev/selected-count"
(cd "$test_root" && PATH="$stub_bin:$PATH" TRACKER_RUN_DIR="$belowcap_run_dir" sh "$test_root/FinalContext.sh") \
  >"$test_root/FinalContext-belowcap.out" 2>"$test_root/FinalContext-belowcap.err" ||
  fail "FinalContext below the cap exited nonzero"
grep -q '^cap_reached: no$' "$test_root/FinalContext-belowcap.out" || fail "FinalContext marked cap_reached yes below the cap"

# Preflight validates the review-loop params before touching git or roborev at all
# (invalid_params below), then names a missing jq before any queue snapshot needs
# it. macOS ships /usr/bin/jq, so the run gets a PATH holding only git, mkdir, and
# the stand-in roborev.
preflight_repo="$test_root/preflight-repo"
git -c init.defaultBranch=main init -q "$preflight_repo"
bare_bin="$test_root/bare-bin"
mkdir -p "$bare_bin"
for tool in git mkdir; do
  ln -s "$(command -v "$tool")" "$bare_bin/$tool"
done
ln -s "$stub_bin/roborev" "$bare_bin/roborev"

# invalid_params cases: a bad value in either param, and either param at or above
# max_restarts, all short-circuit before Preflight ever reads git or roborev.
extract_command Preflight max_reviews=0 max_repairs=3 max_restarts=40
got=$(cd "$preflight_repo" &&
  PATH="$bare_bin" TRACKER_RUN_DIR="$test_root/run-preflight-zero" /bin/sh "$test_root/Preflight.sh")
[ "$got" = invalid_params ] || fail "Preflight with max_reviews=0 printed '$got', want invalid_params"

extract_command Preflight max_reviews=30 max_repairs=abc max_restarts=40
got=$(cd "$preflight_repo" &&
  PATH="$bare_bin" TRACKER_RUN_DIR="$test_root/run-preflight-nan" /bin/sh "$test_root/Preflight.sh")
[ "$got" = invalid_params ] || fail "Preflight with max_repairs=abc printed '$got', want invalid_params"

extract_command Preflight max_reviews=40 max_repairs=3 max_restarts=40
got=$(cd "$preflight_repo" &&
  PATH="$bare_bin" TRACKER_RUN_DIR="$test_root/run-preflight-reviews-ge" /bin/sh "$test_root/Preflight.sh")
[ "$got" = invalid_params ] || fail "Preflight with max_reviews >= max_restarts printed '$got', want invalid_params"

extract_command Preflight max_reviews=30 max_repairs=40 max_restarts=40
got=$(cd "$preflight_repo" &&
  PATH="$bare_bin" TRACKER_RUN_DIR="$test_root/run-preflight-repairs-ge" /bin/sh "$test_root/Preflight.sh")
[ "$got" = invalid_params ] || fail "Preflight with max_repairs >= max_restarts printed '$got', want invalid_params"

extract_command Preflight max_reviews=30 max_repairs=3 max_restarts=40
got=$(cd "$preflight_repo" &&
  PATH="$bare_bin" TRACKER_RUN_DIR="$test_root/run-preflight" /bin/sh "$test_root/Preflight.sh")
[ "$got" = missing_jq ] || fail "Preflight without jq printed '$got', want missing_jq"

# RecordSelection starts a fresh repair budget and clears the previous review's
# logs on every new top-level selection, so no feedback leaks between reviews.
extract_command RecordSelection
record_run_dir="$test_root/run-record"
mkdir -p "$record_run_dir/roborev" "$record_run_dir/SelectReview"
printf 'SELECTION: 91\nSTATUS: success\n' >"$record_run_dir/SelectReview/response.md"
printf '2\n' >"$record_run_dir/roborev/selected-count"
printf '1\n' >"$record_run_dir/roborev/repair-attempts"
printf 'stale verify output\n' >"$record_run_dir/roborev/verify.log"
printf 'stale commit output\n' >"$record_run_dir/roborev/commit.log"
got=$(TRACKER_RUN_DIR="$record_run_dir" sh "$test_root/RecordSelection.sh")
[ "$got" = selected ] || fail "RecordSelection with a valid selection printed '$got', want selected"
[ "$(cat "$record_run_dir/roborev/selected-count")" = 3 ] || fail "RecordSelection did not increment selected-count"
[ "$(cat "$record_run_dir/roborev/repair-attempts")" = 0 ] || fail "RecordSelection did not reset repair-attempts"
[ ! -s "$record_run_dir/roborev/verify.log" ] || fail "RecordSelection did not empty verify.log"
[ ! -s "$record_run_dir/roborev/commit.log" ] || fail "RecordSelection did not empty commit.log"

# RepairBudget gates ImplementFix on an on-disk per-review counter and feeds it the
# previous attempt's verification/commit tails, since ImplementFix's ${ctx.tool_stdout}
# now comes from this node instead of straight from VerifyProject/CommitFix.
extract_command RepairBudget max_repairs=3
repair_run_dir="$test_root/run-repair"
mkdir -p "$repair_run_dir/roborev"
printf '1\n' >"$repair_run_dir/roborev/repair-attempts"
printf 'VERIFY TAIL MARKER\n' >"$repair_run_dir/roborev/verify.log"
printf 'COMMIT TAIL MARKER\n' >"$repair_run_dir/roborev/commit.log"
out=$(TRACKER_RUN_DIR="$repair_run_dir" sh "$test_root/RepairBudget.sh")
[ "$(printf '%s\n' "$out" | tail -n 1)" = repair ] || fail "RepairBudget under budget did not print repair"
[ "$(cat "$repair_run_dir/roborev/repair-attempts")" = 2 ] || fail "RepairBudget did not increment repair-attempts"
printf '%s\n' "$out" | grep -q 'VERIFY TAIL MARKER' ||
  fail "RepairBudget dropped the verification log tail before its marker"
printf '%s\n' "$out" | grep -q 'COMMIT TAIL MARKER' ||
  fail "RepairBudget dropped the commit log tail before its marker"

# At budget, RepairBudget defers instead of trying again, and logs why.
printf '3\n' >"$repair_run_dir/roborev/repair-attempts"
: >"$repair_run_dir/roborev/repair-budget.log"
got=$(TRACKER_RUN_DIR="$repair_run_dir" sh "$test_root/RepairBudget.sh")
[ "$(printf '%s\n' "$got" | tail -n 1)" = exhausted ] || fail "RepairBudget at budget did not print exhausted"
[ "$(cat "$repair_run_dir/roborev/repair-attempts")" = 3 ] || fail "RepairBudget at budget must not increment further"
[ -s "$repair_run_dir/roborev/repair-budget.log" ] || fail "RepairBudget did not log the exhaustion reason"

# An unreadable counter fails closed to exhausted rather than restarting from zero.
printf 'not-a-number\n' >"$repair_run_dir/roborev/repair-attempts"
got=$(TRACKER_RUN_DIR="$repair_run_dir" sh "$test_root/RepairBudget.sh")
[ "$(printf '%s\n' "$got" | tail -n 1)" = exhausted ] ||
  fail "RepairBudget with an unreadable counter printed '$got', want exhausted"

# DeferCurrent stashes uncommitted work outside .tracker before it comments, so the
# next review's `git add -A` can never commit an abandoned repair under the wrong
# job. A stand-in roborev records the comment instead of calling the daemon, so
# the assertions below read exactly what DeferCurrent sent it.
extract_command DeferCurrent
defer_repo="$test_root/defer-repo"
git -c init.defaultBranch=main init -q "$defer_repo"
mkdir -p "$defer_repo/.tracker"
printf 'tracked\n' >"$defer_repo/tracked.txt"
git -C "$defer_repo" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@t add tracked.txt
git -C "$defer_repo" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@t commit -q -m seed

defer_bin="$test_root/defer-bin"
mkdir -p "$defer_bin"
cat >"$defer_bin/roborev" <<'EOF'
#!/bin/sh
if [ "$1" = comment ]; then
  shift
  printf '%s\n' "$@" >"$DEFER_COMMENT_ARGS"
  exit 0
fi
exit 1
EOF
chmod +x "$defer_bin/roborev"

defer_run_dir="$test_root/run-defer"
mkdir -p "$defer_run_dir/roborev"
printf '77\n' >"$defer_run_dir/roborev/current-job"
comment_args="$test_root/defer-comment-args"

# Dirty case: a tracked edit and an untracked file outside .tracker both stash;
# .tracker itself is left alone.
printf 'edited\n' >"$defer_repo/tracked.txt"
printf 'new\n' >"$defer_repo/untracked.txt"
printf 'scratch\n' >"$defer_repo/.tracker/scratch"
(cd "$defer_repo" && PATH="$defer_bin:$PATH" TRACKER_RUN_DIR="$defer_run_dir" \
  DEFER_COMMENT_ARGS="$comment_args" sh "$test_root/DeferCurrent.sh") \
  >"$test_root/DeferCurrent.out" 2>"$test_root/DeferCurrent.err" ||
  fail "DeferCurrent exited nonzero on a dirty tree"
[ "$(tail -n 1 "$test_root/DeferCurrent.out")" = defer_ok ] ||
  fail "DeferCurrent did not end with defer_ok on a dirty tree"
[ "$(cat "$defer_repo/tracked.txt")" = tracked ] || fail "DeferCurrent left the tracked edit unstashed"
[ ! -e "$defer_repo/untracked.txt" ] || fail "DeferCurrent left the untracked file unstashed"
[ -f "$defer_repo/.tracker/scratch" ] || fail "DeferCurrent stashed .tracker"
git -C "$defer_repo" stash list | grep -q 'deferred job 77' || fail "the stash is not named for job 77"
grep -q 'stash@{0}' "$comment_args" || fail "the roborev comment did not name stash@{0}"
grep -q 'deferred job 77' "$comment_args" || fail "the roborev comment did not name the stash message"

# Clean case: nothing outside .tracker is dirty, so no stash is made even though
# .tracker itself still has untracked scratch content.
git -C "$defer_repo" stash clear
printf 'more scratch\n' >"$defer_repo/.tracker/scratch2"
(cd "$defer_repo" && PATH="$defer_bin:$PATH" TRACKER_RUN_DIR="$defer_run_dir" \
  DEFER_COMMENT_ARGS="$comment_args" sh "$test_root/DeferCurrent.sh") \
  >"$test_root/DeferCurrent.out" 2>"$test_root/DeferCurrent.err" ||
  fail "DeferCurrent exited nonzero on a clean tree"
[ "$(tail -n 1 "$test_root/DeferCurrent.out")" = defer_ok ] ||
  fail "DeferCurrent did not end with defer_ok on a clean tree"
[ -z "$(git -C "$defer_repo" stash list)" ] ||
  fail "DeferCurrent stashed a tree that was clean outside .tracker"
