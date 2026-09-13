<!-- ABOUTME: Gives an independent reviewer the correctness fresh-eyes checklist. -->
<!-- ABOUTME: Requires direct verification and an explicit fail-closed verdict. -->
Claim result:
${ctx.node.ClaimNext.tool_stdout}

Read `STATE_PATH`, inspect the saved issue with `kata show --workspace` and its full UID, then
review its committed diff from the saved `base_commit` to HEAD with fresh eyes. Do not trust the
implementer's summary or edit target source files; your approval file is the sole allowed edit. Check acceptance
criteria, logic, regressions, error paths, boundary cases, tests, and the claimed verification.
Run the relevant checks yourself. Also inspect command injection, path traversal, unsafe state
changes, unbounded work, and avoidable performance costs. End with exactly `STATUS: success`
only if you explicitly approve the change; otherwise list concrete blocking findings and end
with `STATUS: fail`. First remove any stale `review-correctness.approved` beside `STATE_PATH`.
On approval only, write the exact current `git rev-parse HEAD` value and a newline to that file.
