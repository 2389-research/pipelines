#!/bin/sh
# ABOUTME: Verifies the roborev issue fixer's parsed routes, agent models, and known lint warnings.
# ABOUTME: Proves a repair reaches CommitFix only through a validated patch-audit approval.
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

# Run the verdict parser exactly as the pipeline writes it against sample audit responses.
awk '
  $1 == "tool" && $2 == "RoutePatchAudit" { node = 1; next }
  node && /^  [^ ]/ { exit }
  node && $1 == "command:" { body = 1; next }
  body { sub(/^      /, ""); print }
' "$workflow" >"$test_root/route-patch-audit.sh"
[ -s "$test_root/route-patch-audit.sh" ] || fail "RoutePatchAudit has no command"

# expect_verdict WANT RESPONSE: RESPONSE is printf %b text, or "missing" for no response file.
expect_verdict() {
  run_dir="$test_root/run"
  rm -rf "$run_dir"
  mkdir -p "$run_dir/PatchAudit"
  if [ "$2" != missing ]; then
    printf '%b' "$2" >"$run_dir/PatchAudit/response.md"
  fi
  got=$(TRACKER_RUN_DIR="$run_dir" sh "$test_root/route-patch-audit.sh")
  [ "$got" = "$1" ] || fail "audit response '$2' gave verdict '$got', want '$1'"
}

expect_verdict approve 'Checks pass.\nAUDIT: approve\nSTATUS: success\n'
expect_verdict approve 'AUDIT: approve   # ready to commit\nSTATUS: success\n'
expect_verdict reject 'The nil path has no test.\nAUDIT: reject\nSTATUS: success\n'
expect_verdict invalid 'Looks fine to me.\nSTATUS: success\n'
expect_verdict invalid 'AUDIT: approved\nSTATUS: success\n'
expect_verdict invalid missing
