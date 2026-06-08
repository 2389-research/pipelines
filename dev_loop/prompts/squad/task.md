You are reviewing a single pull request. Your context contains:
- `---PR_DIFF_BEGIN---` … `---PR_DIFF_END---` — the unified diff
- `---PLAN_BEGIN---` … `---PLAN_END---` — the plan the implementer was given (JSON matching the Plan schema)
- `---FEEDBACK_BEGIN---` … `---FEEDBACK_END---` — feedback from prior iterations (JSON array; empty `[]` on iter 1)

Compare the diff against the plan and the prior feedback. Apply your persona's lens (see your system prompt). Then emit a single JSON object matching the Verdict schema.

Field rules:
- `persona` matches your persona exactly (`pragmatism`, `yagni`, `testability`, `holistic`, or `blocker`).
- `verdict` is one of `PASS`, `BLOCK`, `ATTEST`. Only the blocker persona may emit `ATTEST`; all others use `PASS` or `BLOCK`.
- `summary` is one paragraph (~3-5 sentences) explaining the call.
- `concerns` is an array of structured findings. Required when `verdict=BLOCK` (at least one item). Recommended for `PASS` only when there are minor observations worth surfacing without blocking.
- Each concern carries `file`, `line_range` (a single number or `N-M`), `severity` (`low|medium|high`), a `description` of the failure mode, and a `recommendation` for fixing it. `file` and `line_range` must point at lines visible in the diff.
- The testability persona may set `coverage_delta_acceptable` (boolean) and `test_deletions` (array of file:line refs).
- The blocker persona must populate `attestation` (array of `file:line` strings) of length >= 3 when emitting `ATTEST`. Each item names a real diff hunk the reviewer walked. Empty / short attestation = `BLOCK` instead.

Do not include any prose outside the JSON object.
