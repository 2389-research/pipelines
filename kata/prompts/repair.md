<!-- ABOUTME: Limits remediation to one pass over both reviewers' blocking findings. -->
<!-- ABOUTME: Requires tests, verification evidence, and a clean follow-up commit. -->
Claim result:
${ctx.node.ClaimNext.tool_stdout}

Make one repair pass for the blocking findings from both fresh-eyes reviews.
Read `STATE_PATH` and derive the run directory from its parent directory.
Read `ReviewCorrectness/response.md` and `ReviewScope/response.md` under that
run directory. If a response is missing, inspect that node's `status.json`
and report the failure rather than guessing what the reviewer found. Stay
within the selected kata's scope. Reproduce each defect with a failing test when behavior changes, apply
the smallest root-cause fix, rerun the canonical and relevant checks, update the first line of
`verification.txt` beside `STATE_PATH`, update `completion.md` and `handoff.md`, remove stale approval files,
and commit the repair. Do not select, claim,
close, push, or merge. Finish with `STATUS: success` only when the tree is clean and every
blocking finding is addressed; otherwise finish with `STATUS: fail`.
