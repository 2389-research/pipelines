<!-- ABOUTME: Gives an independent reviewer the scope and maintainability fresh-eyes lens. -->
<!-- ABOUTME: Requires direct verification and an explicit fail-closed verdict. -->
Claim result:
${ctx.node.ClaimNext.tool_stdout}

Read `STATE_PATH`, inspect the saved issue with `kata show --workspace` and its full UID, then
review its committed diff from the saved `base_commit` to HEAD with fresh eyes. Do not trust the
implementer's summary or edit target source files; your approval file is the sole allowed edit. Confirm every changed
line serves the one selected issue, repository rules were followed, existing work was preserved,
and the solution stays simple and maintainable. Check relevant security, correctness, tests,
error handling, resource bounds, and performance. Run the relevant checks yourself. End with
exactly `STATUS: success` only if you explicitly approve the change; otherwise list concrete
blocking findings and end with `STATUS: fail`. First remove any stale `review-scope.approved`
beside `STATE_PATH`. On approval only, write the exact current `git rev-parse HEAD` value and a
newline to that file.
