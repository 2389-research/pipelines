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

# A capped run stops at max_reviews, not when the queue is empty; the docs must
# say so instead of promising to drain the whole queue in one run.
root_readme="$roborev_dir/../README.md"
if grep -q 'runs it until the queue is empty' "$root_readme"; then
  fail "root README.md still promises to drain the whole queue in one run"
fi
if grep -q 'until its roborev queue is empty' "$roborev_dir/README.md"; then
  fail "roborev/README.md still promises to drain the whole queue in one run"
fi
if grep -q 'Fixes and closes every open roborev review' "$roborev_dir/drainrev.sh"; then
  fail "drainrev.sh --help still promises to fix every open review in one run"
fi

# N1: rule 5 (the review_id=0, drain_queue=false stop condition) must ignore
# earlier-run deferrals -- only this run's own COMPLETED/DEFERRED stop it, or
# a repo with any persisted deferral could never select even one review in
# that mode.
if grep -q 'one ID appears in COMPLETED or either DEFERRED list' "$workflow"; then
  fail "SelectReview rule 5 must not count earlier-run deferrals"
fi
grep -q 'one ID appears in COMPLETED or DEFERRED (this run)' "$workflow" ||
  fail "SelectReview rule 5 must count only this run's COMPLETED/DEFERRED"

# Doctor Biz's DeepSeek turn ceilings (kata parity): pin the five raised
# values and the three left unchanged, straight from the .dip text -- these
# never appear on a dippin simulate node_enter event.
agent_max_turns() {
  awk -v node="$1" '
    $1 == "agent" && $2 == node { found = 1; next }
    found && /^  [^ ]/ { exit }
    found && $1 == "max_turns:" { print $2; exit }
  ' "$workflow"
}
[ "$(agent_max_turns Triage)" = 100 ] || fail "Triage's max_turns is not pinned to 100"
[ "$(agent_max_turns PatchAudit)" = 100 ] || fail "PatchAudit's max_turns is not pinned to 100"
[ "$(agent_max_turns NoOracleAudit)" = 100 ] || fail "NoOracleAudit's max_turns is not pinned to 100"
[ "$(agent_max_turns AuditReReview)" = 100 ] || fail "AuditReReview's max_turns is not pinned to 100"
[ "$(agent_max_turns ImplementFix)" = 300 ] || fail "ImplementFix's max_turns is not pinned to 300"
[ "$(agent_max_turns SelectReview)" = 12 ] || fail "SelectReview's max_turns must stay 12"
[ "$(agent_max_turns FinalAudit)" = 14 ] || fail "FinalAudit's max_turns must stay 14"
[ "$(agent_max_turns Abort)" = 2 ] || fail "Abort's max_turns must stay 2"

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

# A Triage failure (STATUS: fail or a turn-limit breach) defers just that one
# review instead of aborting the whole drain.
jq -se '
  any(.[]; .event == "edge_traverse" and .from == "Triage" and .to == "DeferCurrent" and .condition == "ctx.outcome = fail")
' "$test_root/events" >/dev/null || fail "Triage must route a failed outcome to DeferCurrent, not Abort"

# DiffGate catches a secret-named file before any packet is built (N4).
jq -se '
  any(.[]; .event == "edge_traverse" and .from == "DiffGate" and .to == "DeferCurrent" and .condition == "ctx.tool_marker = secret_risk")
' "$test_root/events" >/dev/null || fail "DiffGate must route secret_risk to DeferCurrent"

# A failed git add -A in DiffGate (N3) must abort, never silently proceed.
jq -se '
  any(.[]; .event == "edge_traverse" and .from == "DiffGate" and .to == "Abort" and .condition == "ctx.tool_marker = add_failed")
' "$test_root/events" >/dev/null || fail "DiffGate must route add_failed to Abort"

# A tree that changed after DiffGate's audit (the post-audit gap) must abort
# instead of committing.
jq -se '
  any(.[]; .event == "edge_traverse" and .from == "CommitFix" and .to == "Abort" and .condition == "ctx.tool_marker = changed_after_audit")
' "$test_root/events" >/dev/null || fail "CommitFix must route changed_after_audit to Abort"

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
  grep -qF -- '--- DEFERRED IDS (this run) ---' "$test_root/$node.out" ||
    fail "$node dropped the this-run deferred heading"
  grep -qF -- '--- DEFERRED IDS (earlier runs) ---' "$test_root/$node.out" ||
    fail "$node dropped the earlier-run deferred heading"
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

# An unreadable selected-count fails closed: QueueContext caps the run rather than
# resuming at 0, and FinalContext reports the cap as unknown (N5) rather than open.
extract_command QueueContext max_reviews=30
unreadable_run_dir="$test_root/run-queue-unreadable"
mkdir -p "$unreadable_run_dir/roborev"
printf 'garbage\n' >"$unreadable_run_dir/roborev/selected-count"
got=$(cd "$test_root" && PATH="$stub_bin:$PATH" TRACKER_RUN_DIR="$unreadable_run_dir" sh "$test_root/QueueContext.sh")
[ "$got" = review_cap ] || fail "QueueContext with an unreadable selected-count printed '$got', want review_cap"
[ ! -e "$unreadable_run_dir/roborev/open.json" ] ||
  fail "QueueContext called roborev with an unreadable selected-count"
[ -s "$unreadable_run_dir/roborev/queue-context.log" ] ||
  fail "QueueContext did not log the unreadable selected-count"

extract_command FinalContext max_reviews=30
final_unreadable_run_dir="$test_root/run-final-unreadable"
mkdir -p "$final_unreadable_run_dir/roborev"
printf 'garbage\n' >"$final_unreadable_run_dir/roborev/selected-count"
(cd "$test_root" && PATH="$stub_bin:$PATH" TRACKER_RUN_DIR="$final_unreadable_run_dir" sh "$test_root/FinalContext.sh") \
  >"$test_root/FinalContext-unreadable.out" 2>"$test_root/FinalContext-unreadable.err" ||
  fail "FinalContext with an unreadable selected-count exited nonzero"
# N5: cap_reached: unknown (not yes) so FinalAudit can never read this as a
# successfully capped drain.
grep -q '^cap_reached: unknown$' "$test_root/FinalContext-unreadable.out" ||
  fail "FinalContext did not report cap_reached: unknown on an unreadable selected-count"
[ -s "$final_unreadable_run_dir/roborev/final-context.log" ] ||
  fail "FinalContext did not log the unreadable selected-count"

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

# full_bin adds jq/cat/cp/dirname/tail/wc/tr to bare_bin's git/mkdir/roborev-
# stand-in, so Preflight can run all the way to its state resets (ok) instead
# of stopping at missing_jq; cat is also what the roborev stand-in itself
# shells out to, and dirname/tail/wc/tr are what the exclude write's
# mkdir-p / no-final-newline check use.
full_bin="$test_root/full-bin"
mkdir -p "$full_bin"
for tool in git mkdir jq cat cp dirname tail wc tr; do
  ln -s "$(command -v "$tool")" "$full_bin/$tool"
done
ln -s "$stub_bin/roborev" "$full_bin/roborev"

# C1: Preflight makes an unignored .tracker/ git-ignored (appended to
# .git/info/exclude) before the cleanliness check, so every git command later
# in the run can rely on .tracker/ being invisible instead of carrying its own
# :(exclude) pathspec.
exclude_repo="$test_root/exclude-repo"
git -c init.defaultBranch=main init -q "$exclude_repo"
git -C "$exclude_repo" config user.name t
git -C "$exclude_repo" config user.email t@t
printf 'seed\n' >"$exclude_repo/seed.txt"
git -C "$exclude_repo" -c core.hooksPath=/dev/null add seed.txt
git -C "$exclude_repo" -c core.hooksPath=/dev/null commit -q -m seed
mkdir -p "$exclude_repo/.tracker"
git -C "$exclude_repo" check-ignore -q .tracker &&
  fail "test setup bug: .tracker/ was already ignored in exclude_repo"
(cd "$exclude_repo" && PATH="$full_bin" TRACKER_RUN_DIR="$test_root/run-exclude" /bin/sh "$test_root/Preflight.sh") \
  >/dev/null 2>&1 || true
git -C "$exclude_repo" check-ignore -q .tracker || fail "Preflight did not make .tracker/ git-ignored"

# I1: Preflight seeds this run's deferred-earlier list from the repo-root
# ledger without touching $STATE/deferred, which stays this run's own, empty.
ok_repo="$test_root/ok-repo"
git -c init.defaultBranch=main init -q "$ok_repo"
git -C "$ok_repo" config user.name t
git -C "$ok_repo" config user.email t@t
printf 'seed\n' >"$ok_repo/seed.txt"
git -C "$ok_repo" -c core.hooksPath=/dev/null add seed.txt
git -C "$ok_repo" -c core.hooksPath=/dev/null commit -q -m seed
mkdir -p "$ok_repo/.tracker/roborev"
printf '11\n22\n' >"$ok_repo/.tracker/roborev/deferred"
ok_run_dir="$test_root/run-ok"
got=$(cd "$ok_repo" && PATH="$full_bin" TRACKER_RUN_DIR="$ok_run_dir" /bin/sh "$test_root/Preflight.sh")
[ "$got" = ok ] || fail "Preflight in a clean, fully-equipped repo printed '$got', want ok"
printf '11\n22\n' >"$test_root/want-deferred-earlier"
diff "$test_root/want-deferred-earlier" "$ok_run_dir/roborev/deferred-earlier" >/dev/null ||
  fail "Preflight did not seed deferred-earlier from the repo-root ledger"
[ ! -s "$ok_run_dir/roborev/deferred" ] || fail "Preflight's fresh deferred ledger should start empty"

# N2: the exclude write creates .git/info when a repo (e.g. made from an
# empty template) does not have it yet.
noinfo_repo="$test_root/noinfo-repo"
git -c init.defaultBranch=main init -q "$noinfo_repo"
git -C "$noinfo_repo" config user.name t
git -C "$noinfo_repo" config user.email t@t
printf 'seed\n' >"$noinfo_repo/seed.txt"
git -C "$noinfo_repo" -c core.hooksPath=/dev/null add seed.txt
git -C "$noinfo_repo" -c core.hooksPath=/dev/null commit -q -m seed
rm -rf "$noinfo_repo/.git/info"
noinfo_run_dir="$test_root/run-noinfo"
got=$(cd "$noinfo_repo" && PATH="$full_bin" TRACKER_RUN_DIR="$noinfo_run_dir" /bin/sh "$test_root/Preflight.sh")
[ "$got" = ok ] || fail "Preflight with a missing .git/info printed '$got', want ok"
git -C "$noinfo_repo" check-ignore -q .tracker ||
  fail "Preflight did not create .git/info and ignore .tracker/ there"

# N2: the exclude write never corrupts an existing exclude file's last line
# when that line does not end in a newline (the naive form would fuse
# *.log with .tracker/ into *.log.tracker/, breaking the user's rule).
nonewline_repo="$test_root/nonewline-repo"
git -c init.defaultBranch=main init -q "$nonewline_repo"
git -C "$nonewline_repo" config user.name t
git -C "$nonewline_repo" config user.email t@t
printf 'seed\n' >"$nonewline_repo/seed.txt"
git -C "$nonewline_repo" -c core.hooksPath=/dev/null add seed.txt
git -C "$nonewline_repo" -c core.hooksPath=/dev/null commit -q -m seed
printf '*.log' >"$nonewline_repo/.git/info/exclude"
printf 'x\n' >"$nonewline_repo/debug.log"
nonewline_run_dir="$test_root/run-nonewline"
got=$(cd "$nonewline_repo" && PATH="$full_bin" TRACKER_RUN_DIR="$nonewline_run_dir" /bin/sh "$test_root/Preflight.sh")
[ "$got" = ok ] || fail "Preflight with a no-final-newline exclude file printed '$got', want ok"
grep -qxF '*.log' "$nonewline_repo/.git/info/exclude" ||
  fail "Preflight corrupted the user's existing *.log ignore rule"
grep -qxF '.tracker/' "$nonewline_repo/.git/info/exclude" ||
  fail "Preflight did not append a clean .tracker/ line"
git -C "$nonewline_repo" check-ignore -q debug.log ||
  fail "the user's *.log rule stopped working after Preflight's write"

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
printf 'stale/secret.env\n' >"$record_run_dir/roborev/secret-risk-paths"
got=$(TRACKER_RUN_DIR="$record_run_dir" sh "$test_root/RecordSelection.sh")
[ "$got" = selected ] || fail "RecordSelection with a valid selection printed '$got', want selected"
[ "$(cat "$record_run_dir/roborev/selected-count")" = 3 ] || fail "RecordSelection did not increment selected-count"
[ "$(cat "$record_run_dir/roborev/repair-attempts")" = 0 ] || fail "RecordSelection did not reset repair-attempts"
[ ! -s "$record_run_dir/roborev/verify.log" ] || fail "RecordSelection did not empty verify.log"
[ ! -s "$record_run_dir/roborev/commit.log" ] || fail "RecordSelection did not empty commit.log"
[ ! -s "$record_run_dir/roborev/secret-risk-paths" ] || fail "RecordSelection did not empty secret-risk-paths"

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
printf '.tracker/\n' >"$defer_repo/.gitignore"
printf 'tracked\n' >"$defer_repo/tracked.txt"
git -C "$defer_repo" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@t add .gitignore tracked.txt
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
# .tracker itself is left alone. Also covers M2 (stash named by SHA, not the
# stale stash@{0}), I1 (persisted to the repo-root ledger), and M3 (a
# secret-risk path, when CommitFix left one, is named in the comment).
printf 'edited\n' >"$defer_repo/tracked.txt"
printf 'new\n' >"$defer_repo/untracked.txt"
printf 'scratch\n' >"$defer_repo/.tracker/scratch"
printf 'app/.env\n' >"$defer_run_dir/roborev/secret-risk-paths"
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
stash_sha=$(git -C "$defer_repo" rev-parse -q --verify refs/stash) || fail "no stash entry was created"
grep -qF "$stash_sha" "$comment_args" || fail "the roborev comment did not name the stash SHA"
grep -q 'deferred job 77' "$comment_args" || fail "the roborev comment did not name the stash message"
if grep -q 'stash@{0}' "$comment_args"; then
  fail "the roborev comment still names the stash by its unstable stash@{0} index"
fi
grep -qF 'app/.env' "$comment_args" || fail "the roborev comment did not name the secret-risk path"
grep -qx 77 "$defer_repo/.tracker/roborev/deferred" ||
  fail "DeferCurrent did not persist the deferral to the repo-root ledger"

# Clean case: nothing outside .tracker is dirty, so no stash is made even though
# .tracker itself still has untracked scratch content.
git -C "$defer_repo" stash clear
: >"$defer_run_dir/roborev/secret-risk-paths"
printf 'more scratch\n' >"$defer_repo/.tracker/scratch2"
(cd "$defer_repo" && PATH="$defer_bin:$PATH" TRACKER_RUN_DIR="$defer_run_dir" \
  DEFER_COMMENT_ARGS="$comment_args" sh "$test_root/DeferCurrent.sh") \
  >"$test_root/DeferCurrent.out" 2>"$test_root/DeferCurrent.err" ||
  fail "DeferCurrent exited nonzero on a clean tree"
[ "$(tail -n 1 "$test_root/DeferCurrent.out")" = defer_ok ] ||
  fail "DeferCurrent did not end with defer_ok on a clean tree"
[ -z "$(git -C "$defer_repo" stash list)" ] ||
  fail "DeferCurrent stashed a tree that was clean outside .tracker"

# C1 (unignored control): after Preflight's exclude-write runs in a repo where
# .tracker/ was NOT already ignored, DeferCurrent's stash still succeeds there
# -- proving the exclude write, not just an already-ignored fixture, is what
# makes this work.
unignored_repo="$test_root/unignored-repo"
git -c init.defaultBranch=main init -q "$unignored_repo"
git -C "$unignored_repo" config user.name t
git -C "$unignored_repo" config user.email t@t
printf 'tracked\n' >"$unignored_repo/tracked.txt"
git -C "$unignored_repo" -c core.hooksPath=/dev/null add tracked.txt
git -C "$unignored_repo" -c core.hooksPath=/dev/null commit -q -m seed
mkdir -p "$unignored_repo/.tracker"
printf 'scratch\n' >"$unignored_repo/.tracker/scratch"
unignored_run_dir="$test_root/run-unignored"
git -C "$unignored_repo" check-ignore -q .tracker &&
  fail "test setup bug: .tracker/ was already ignored in unignored_repo"
(cd "$unignored_repo" && PATH="$full_bin" TRACKER_RUN_DIR="$unignored_run_dir" /bin/sh "$test_root/Preflight.sh") \
  >/dev/null 2>&1 || true
git -C "$unignored_repo" check-ignore -q .tracker ||
  fail "Preflight did not make the unignored .tracker/ git-ignored"

printf '79\n' >"$unignored_run_dir/roborev/current-job"
printf 'edited\n' >"$unignored_repo/tracked.txt"
printf 'new\n' >"$unignored_repo/untracked.txt"
(cd "$unignored_repo" && PATH="$defer_bin:$PATH" TRACKER_RUN_DIR="$unignored_run_dir" \
  DEFER_COMMENT_ARGS="$comment_args" sh "$test_root/DeferCurrent.sh") \
  >"$test_root/DeferCurrent-unignored.out" 2>"$test_root/DeferCurrent-unignored.err" ||
  fail "DeferCurrent exited nonzero after Preflight ignored .tracker/"
[ "$(tail -n 1 "$test_root/DeferCurrent-unignored.out")" = defer_ok ] ||
  fail "DeferCurrent did not end with defer_ok after Preflight ignored .tracker/"
[ ! -e "$unignored_repo/untracked.txt" ] ||
  fail "DeferCurrent left the untracked file unstashed after Preflight ignored .tracker/"
[ -f "$unignored_repo/.tracker/scratch" ] ||
  fail "DeferCurrent stashed .tracker after Preflight ignored it"

# M1: a git status that fails outright is never read as a clean tree. A
# stand-in git delegates every subcommand to the real one except status, which
# it always fails, so DeferCurrent's own cleanliness check cannot succeed.
fail_status_bin="$test_root/fail-status-bin"
mkdir -p "$fail_status_bin"
real_git=$(command -v git)
cat >"$fail_status_bin/git" <<EOF
#!/bin/sh
if [ "\$1" = status ]; then
  echo 'probe: forced status failure' >&2
  exit 129
fi
exec $real_git "\$@"
EOF
chmod +x "$fail_status_bin/git"
status_fail_run_dir="$test_root/run-defer-statusfail"
mkdir -p "$status_fail_run_dir/roborev"
printf '80\n' >"$status_fail_run_dir/roborev/current-job"
got=$(cd "$defer_repo" && PATH="$fail_status_bin:$defer_bin:$PATH" TRACKER_RUN_DIR="$status_fail_run_dir" \
  DEFER_COMMENT_ARGS="$comment_args" sh "$test_root/DeferCurrent.sh")
[ "$got" = defer_error ] ||
  fail "DeferCurrent with a failing git status printed '$got', want defer_error"
# N6: a defer_error must never persist to the repo-level ledger -- only a
# fully successful defer_ok does, so a review is never silently hidden under
# "earlier runs" with no comment ever explaining why.
grep -qx 80 "$defer_repo/.tracker/roborev/deferred" &&
  fail "DeferCurrent persisted job 80 to the repo ledger despite a defer_error"

# Triage -> DeferCurrent (a STATUS: fail or turn-limit breach defers that one
# review instead of aborting the whole drain). RecordSelection resets
# $STATE/triage.md per review, so on this path it is empty; DeferCurrent's
# comment must fall back to Triage's own partial response and say why.
triage_fail_run_dir="$test_root/run-defer-triagefail"
mkdir -p "$triage_fail_run_dir/roborev" "$triage_fail_run_dir/Triage"
printf '81\n' >"$triage_fail_run_dir/roborev/current-job"
: >"$triage_fail_run_dir/roborev/triage.md"
printf 'PARTIAL-TRIAGE-CONTENT: findings 1-2 of 5 validated so far.\n' \
  >"$triage_fail_run_dir/Triage/response.md"
(cd "$defer_repo" && PATH="$defer_bin:$PATH" TRACKER_RUN_DIR="$triage_fail_run_dir" \
  DEFER_COMMENT_ARGS="$comment_args" sh "$test_root/DeferCurrent.sh") \
  >"$test_root/DeferCurrent-triagefail.out" 2>"$test_root/DeferCurrent-triagefail.err" ||
  fail "DeferCurrent exited nonzero on a Triage-failure defer"
[ "$(tail -n 1 "$test_root/DeferCurrent-triagefail.out")" = defer_ok ] ||
  fail "DeferCurrent did not end with defer_ok on a Triage-failure defer"
grep -q 'did not finish validating' "$comment_args" ||
  fail "the roborev comment did not say triage could not finish"
grep -qF 'PARTIAL-TRIAGE-CONTENT' "$comment_args" ||
  fail "the roborev comment did not carry Triage's partial response"

# I3 + C1: DiffGate stages with git add -A and audits git diff --cached, so a
# brand-new untracked file's contents (not just its ?? status line) reach
# PatchAudit's packet, and .tracker/ (git-ignored) is never staged.
extract_command DiffGate
diff_repo="$test_root/diff-repo"
git -c init.defaultBranch=main init -q "$diff_repo"
printf '.tracker/\n' >"$diff_repo/.gitignore"
printf 'seed\n' >"$diff_repo/seed.txt"
git -C "$diff_repo" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@t add .gitignore seed.txt
git -C "$diff_repo" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@t commit -q -m seed
mkdir -p "$diff_repo/.tracker"
printf 'scratch\n' >"$diff_repo/.tracker/scratch"

diff_run_dir="$test_root/run-diffgate"
mkdir -p "$diff_run_dir/roborev"
git -C "$diff_repo" rev-parse HEAD >"$diff_run_dir/roborev/expected-head"
printf '55\n' >"$diff_run_dir/roborev/current-job"
: >"$diff_run_dir/roborev/triage.md"
: >"$diff_run_dir/roborev/verify.log"

# no_changes: nothing touched yet.
got=$(cd "$diff_repo" && TRACKER_RUN_DIR="$diff_run_dir" sh "$test_root/DiffGate.sh")
[ "$got" = no_changes ] || fail "DiffGate on a clean tree printed '$got', want no_changes"

# diff_safe: a brand-new untracked file's own content must appear in the DIFF
# section, which only staging (git add -A) before diffing (git diff --cached)
# can show for a wholly-new file.
printf 'NEW-FILE-MARKER-CONTENT\n' >"$diff_repo/brand_new.txt"
out=$(cd "$diff_repo" && TRACKER_RUN_DIR="$diff_run_dir" sh "$test_root/DiffGate.sh")
[ "$(printf '%s\n' "$out" | tail -n 1)" = diff_safe ] ||
  fail "DiffGate with a new untracked file did not end with diff_safe"
printf '%s\n' "$out" | grep -q 'NEW-FILE-MARKER-CONTENT' ||
  fail "DiffGate's packet did not include the new file's content"
printf '%s\n' "$out" | grep -q '^+NEW-FILE-MARKER-CONTENT$' ||
  fail "DiffGate's DIFF section did not show the new file as an added hunk"
git -C "$diff_repo" diff --cached --name-only | grep -qx '.tracker/scratch' &&
  fail "DiffGate staged .tracker even though it was gitignored"

# I3: CommitFix commits exactly the index DiffGate staged (same git add -A),
# and C1: a git-ignored .tracker/ is left alone by both.
extract_command CommitFix
commit_repo="$test_root/commit-repo"
git -c init.defaultBranch=main init -q "$commit_repo"
git -C "$commit_repo" config user.name t
git -C "$commit_repo" config user.email t@t
git -C "$commit_repo" config core.hooksPath /dev/null
printf '.tracker/\n' >"$commit_repo/.gitignore"
printf 'seed\n' >"$commit_repo/seed.txt"
git -C "$commit_repo" add .gitignore seed.txt
git -C "$commit_repo" commit -q -m seed
mkdir -p "$commit_repo/.tracker"
printf 'scratch\n' >"$commit_repo/.tracker/scratch"
printf 'fixed\n' >"$commit_repo/seed.txt"
printf 'new\n' >"$commit_repo/new.txt"

commit_run_dir="$test_root/run-commit"
mkdir -p "$commit_run_dir/roborev" "$commit_run_dir/PatchAudit"
git -C "$commit_repo" rev-parse HEAD >"$commit_run_dir/roborev/expected-head"
printf '56\n' >"$commit_run_dir/roborev/current-job"
printf 'AUDIT: approve\nSTATUS: success\n' >"$commit_run_dir/PatchAudit/response.md"
# Mirrors what DiffGate itself would have done: stage, then save the audited
# tree, and leave the index staged for CommitFix's own git add -A to repeat.
git -C "$commit_repo" add -A
git -C "$commit_repo" write-tree >"$commit_run_dir/roborev/audited-tree"
got=$(cd "$commit_repo" && TRACKER_RUN_DIR="$commit_run_dir" sh "$test_root/CommitFix.sh")
[ "$got" = commit_ok ] || fail "CommitFix with .tracker/ gitignored printed '$got', want commit_ok"
git -C "$commit_repo" show --stat HEAD | grep -q 'new.txt' ||
  fail "CommitFix did not commit the new file with .tracker/ gitignored"
git -C "$commit_repo" show --stat HEAD | grep -q '\.tracker' &&
  fail "CommitFix committed something under .tracker even though it was gitignored"
[ -f "$commit_repo/.tracker/scratch" ] ||
  fail "CommitFix removed .tracker/scratch even though it only commits"

# Post-audit gap: if the tree changes after DiffGate saved audited-tree (e.g.
# PatchAudit's own tool access touching a file), CommitFix must refuse to
# commit the unaudited result instead of committing it.
printf 'audited version\n' >"$commit_repo/tampered.txt"
git -C "$commit_repo" add -A
tampered_run_dir="$test_root/run-commit-tampered"
mkdir -p "$tampered_run_dir/roborev" "$tampered_run_dir/PatchAudit"
git -C "$commit_repo" rev-parse HEAD >"$tampered_run_dir/roborev/expected-head"
printf '57\n' >"$tampered_run_dir/roborev/current-job"
printf 'AUDIT: approve\nSTATUS: success\n' >"$tampered_run_dir/PatchAudit/response.md"
git -C "$commit_repo" write-tree >"$tampered_run_dir/roborev/audited-tree"
printf 'changed after audit\n' >"$commit_repo/tampered.txt"
before_head=$(git -C "$commit_repo" rev-parse HEAD)
got=$(cd "$commit_repo" && TRACKER_RUN_DIR="$tampered_run_dir" sh "$test_root/CommitFix.sh")
[ "$got" = changed_after_audit ] ||
  fail "CommitFix after a post-audit change printed '$got', want changed_after_audit"
after_head=$(git -C "$commit_repo" rev-parse HEAD)
[ "$before_head" = "$after_head" ] || fail "CommitFix committed a change made after the audit"
grep -q 'tampered.txt' "$tampered_run_dir/roborev/commit.log" ||
  fail "CommitFix did not name the changed path after a post-audit change"
git -C "$commit_repo" reset -q --hard "$before_head"

# N3: a failed git add -A (e.g. a background process briefly holding
# .git/index.lock) must abort instead of reading as no_changes or building a
# packet from a stale index.
lock_run_dir="$test_root/run-diffgate-lock"
mkdir -p "$lock_run_dir/roborev"
git -C "$diff_repo" rev-parse HEAD >"$lock_run_dir/roborev/expected-head"
printf '59\n' >"$lock_run_dir/roborev/current-job"
: >"$lock_run_dir/roborev/triage.md"
: >"$lock_run_dir/roborev/verify.log"
printf 'LOCKED-ATTEMPT\n' >"$diff_repo/locked.txt"
: >"$diff_repo/.git/index.lock"
# git reset -q (DiffGate's own belt-and-suspenders cleanup on a failed add)
# also fails while the lock is held; redirect it like every other stderr in
# this file so that expected noise never reaches the test's own output.
got=$(cd "$diff_repo" && TRACKER_RUN_DIR="$lock_run_dir" sh "$test_root/DiffGate.sh" 2>"$test_root/DiffGate-lock.err")
rm -f "$diff_repo/.git/index.lock"
[ "$got" = add_failed ] || fail "DiffGate with a held index.lock printed '$got', want add_failed"

# N4: DiffGate catches a secret-named file before any packet content is
# built, so its value never reaches PatchAudit's prompt (stdout) or
# repair.diff -- CommitFix's own check still runs too (M3).
secret_repo="$test_root/diffgate-secret-repo"
git -c init.defaultBranch=main init -q "$secret_repo"
printf '.tracker/\n' >"$secret_repo/.gitignore"
printf 'seed\n' >"$secret_repo/seed.txt"
git -C "$secret_repo" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@t add .gitignore seed.txt
git -C "$secret_repo" -c core.hooksPath=/dev/null -c user.name=t -c user.email=t@t commit -q -m seed
secret_run_dir="$test_root/run-diffgate-secret"
mkdir -p "$secret_run_dir/roborev"
git -C "$secret_repo" rev-parse HEAD >"$secret_run_dir/roborev/expected-head"
printf '60\n' >"$secret_run_dir/roborev/current-job"
: >"$secret_run_dir/roborev/triage.md"
: >"$secret_run_dir/roborev/verify.log"
mkdir -p "$secret_repo/app"
printf 'TOKEN=SECRET-MARKER-VALUE\n' >"$secret_repo/app/.env"
out=$(cd "$secret_repo" && TRACKER_RUN_DIR="$secret_run_dir" sh "$test_root/DiffGate.sh")
[ "$(printf '%s\n' "$out" | tail -n 1)" = secret_risk ] ||
  fail "DiffGate with a new .env did not end with secret_risk"
printf '%s\n' "$out" | grep -q 'SECRET-MARKER-VALUE' &&
  fail "DiffGate's stdout leaked the secret file's value"
[ ! -f "$secret_run_dir/roborev/repair.diff" ] ||
  fail "DiffGate wrote repair.diff before its secret check"
grep -qF 'app/.env' "$secret_run_dir/roborev/secret-risk-paths" ||
  fail "DiffGate did not record the secret-risk path"
