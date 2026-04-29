# Proposed changes — discovered during runner test (Apr 2026)

Captured during end-to-end runs of `architect+Sonnet → qwen runner` on NIFB sprints. Changes here are forward-looking design improvements; the immediate runner reliability work (patch_file validation, git rollback) is tracked separately.

## Bucket: How sprints should be designed (context-handling)

### Per-file context slicing for the local runner

**Problem observed:** Today the runner sends qwen the entire 25-35 KB sprint markdown for every per-file Ollama call. That's ~5× more context than qwen needs and contributes to attention-degradation failures (e.g., qwen pasting markdown content into trivial Python files, or confusing path labels with file content during patches).

**Proposed structure:** Three-tier context per Ollama call.

| Tier | Sections | Rationale |
|---|---|---|
| **Always include (cross-cutting)** | Project conventions header, cross-sprint dependencies (symbols/paths available from prior sprints), `## Interface contract` (full — this is the sprint's API surface) | Cross-file knowledge tests + consumer files need to write correct sibling references |
| **Per-file slice** | `## Imports per file` (entry for `$filepath` only), `## Algorithm notes` (entry for `$filepath` only), `## Test plan` (entry for `$filepath` if it's a test file) | These sections are already keyed by path — slicing is mechanical, no cross-file loss |
| **Drop entirely** | `## Scope`, `## Non-goals`, `## DoD`, `## Validation`, `## Expected Artifacts` | Sprint-level orientation/outcomes that don't shape file-level code |

**Size estimate:** ~3-8 KB per call (vs ~25-35 KB today). ~5× reduction.

**Why keep `## Interface contract` shared, not sliced:**
- Test files need sibling-file signatures (e.g. `test_auth.py` needs to know what `POST /auth/otp/send` returns)
- Router files need adjacent model field sets (e.g. `routers/locations.py` queries against `Station` from `models.py`)
- Strict slicing here causes qwen to invent imagined response shapes / field names

**Edge case — Modified files:** for `patch_file` calls, qwen already sees the existing file content; that implicitly carries "what's already there." Slicing can be more aggressive on the Modified path.

### Architect-side requirements that enable slicing

For the slicing to work cleanly, the architect (Opus → Sonnet) must keep producing sprints with consistent structure:

- `## Interface contract` blocks must be introduced by `### \`path/to/file\`` subheadings (so awk can extract per-file entries when needed for Modified path or test-file slices)
- `## Imports per file` must label each block with the file path in backticks
- `## Algorithm notes` likewise
- `## Test plan` likewise — and tests should be grouped by the file under test, not by feature

These are already mostly true in current outputs; codify them in the tool's system prompt so all generators stay consistent.

### Implementation notes (when this gets built)

- ~30-50 lines of awk in `gen_file` and `patch_file` to extract per-file slices
- Drop the entire-sprint `${SPRINT}` variable from the qwen prompt; build a `${SPRINT_SLICE}` variable instead
- Include a `### Sibling file API surface` block at the top of `${SPRINT_SLICE}` that lists exported types/functions from sibling files in this sprint (one line per export, no implementation)
- Validate per-sprint that the awk extraction yielded non-empty blocks for every file in `## New files` + `## Modified files`. If extraction fails for a file, fall back to the full-sprint context (don't break the run).

## Status

**Not yet implemented.** Captured here as design rationale; will inform the next runner upgrade pass after the validation/rollback work lands.

The validation/rollback work is independent — it makes the patch_file path correct for any context size. Slicing is an *additional* reliability improvement that reduces the failure rate but doesn't replace the need for postcondition checks.
