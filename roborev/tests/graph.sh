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

# extract_command NODE: write the tool node's command, dedented, to $test_root/NODE.sh.
extract_command() {
  awk -v node="$1" '
    $1 == "tool" && $2 == node { found = 1; next }
    found && /^  [^ ]/ { exit }
    found && $1 == "command:" { body = 1; next }
    body { sub(/^      /, ""); print }
  ' "$workflow" >"$test_root/$1.sh"
  [ -s "$test_root/$1.sh" ] || fail "$1 has no command"
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

# expect_queue_snapshot NODE MARKER SAVED: the node keeps the full list in roborev/SAVED but
# prints only per-review selection fields. Forty open reviews once put 1.3 MB of job
# prompts into SelectReview and overflowed DeepSeek's 1M-token context.
expect_queue_snapshot() {
  extract_command "$1"
  run_dir="$test_root/run-$1"
  mkdir -p "$run_dir/roborev"
  (cd "$test_root" && PATH="$stub_bin:$PATH" TRACKER_RUN_DIR="$run_dir" sh "$test_root/$1.sh") \
    >"$test_root/$1.out" 2>"$test_root/$1.err" || fail "$1 exited nonzero"
  [ "$(tail -n 1 "$test_root/$1.out")" = "$2" ] || fail "$1 did not end with $2"
  if grep -q REVIEW-PROMPT-BODY "$test_root/$1.out"; then
    fail "$1 passed job prompts to the agent"
  fi
  grep -q '"id":61,"git_ref":"929d219"' "$test_root/$1.out" || fail "$1 dropped review 61"
  grep -q '"verdict":"P"' "$test_root/$1.out" || fail "$1 dropped review 64's verdict"
  grep -q REVIEW-PROMPT-BODY "$run_dir/roborev/$3" || fail "$1 did not keep the full list in $3"
}

expect_queue_snapshot QueueContext queue_ready open.json
expect_queue_snapshot FinalContext final_ready final-open.json

# Preflight names a missing jq before any queue snapshot needs it. macOS ships /usr/bin/jq,
# so the run gets a PATH holding only git, mkdir, and the stand-in roborev.
extract_command Preflight
preflight_repo="$test_root/preflight-repo"
git -c init.defaultBranch=main init -q "$preflight_repo"
bare_bin="$test_root/bare-bin"
mkdir -p "$bare_bin"
for tool in git mkdir; do
  ln -s "$(command -v "$tool")" "$bare_bin/$tool"
done
ln -s "$stub_bin/roborev" "$bare_bin/roborev"
got=$(cd "$preflight_repo" &&
  PATH="$bare_bin" TRACKER_RUN_DIR="$test_root/run-preflight" /bin/sh "$test_root/Preflight.sh")
[ "$got" = missing_jq ] || fail "Preflight without jq printed '$got', want missing_jq"
