#!/usr/bin/env bats
# test_dipx_invariants.bats — source-shape guards for the .dipx packed-bundle
# path. dippin pack corrupts single-quoted YAML scalars (dippin-lang#114) and
# tracker's denylist refuses any `exec N>` redirect (tracker#333). These two
# tests freeze the dev_loop-side workarounds so a future edit can't silently
# reintroduce either failure mode.

@test "every marker_grep in dev_loop.dip uses double-quoted form" {
  DIP="${BATS_TEST_DIRNAME}/../dev_loop.dip"
  [ -f "${DIP}" ]
  # Any `marker_grep: '...'` (single-quoted) would be corrupted when packed
  # by dippin (single quotes embedded literally into the .dipx scalar).
  ! grep -nE "^[[:space:]]*marker_grep: '" "${DIP}"
  # And the expected double-quoted form covers every marker_grep line.
  total=$(grep -cE "^[[:space:]]*marker_grep:" "${DIP}")
  dq=$(grep -cE "^[[:space:]]*marker_grep: \"" "${DIP}")
  [ "${total}" = "${dq}" ]
}

@test "setup_run.sh contains no 'exec N>' fd-redirect pattern" {
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/setup_run.sh"
  [ -f "${SCRIPT}" ]
  # tracker's safety denylist refuses any `exec N<` / `exec N>` redirect in
  # packed .dipx workflows. The brace-group `{ ... } > file` idiom achieves
  # the same atomic-write semantics without this construct.
  ! grep -nE 'exec[[:space:]]+[0-9]+[<>]' "${SCRIPT}"
}
