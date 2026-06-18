# Repo conventions template

Project-specific facts the dev_loop Implementer + 5-persona squad reviewers
need. The universal rules (Conventional Commits, no `--no-verify`, no
amending published commits, tests fail→pass, no emojis) live in the
persona prompts themselves; this file carries only project-specific
overlays. Replace with your repo's facts before running dev_loop, or
drop `.dev_loop/conventions.md` / `AGENTS.md` / `CLAUDE.md` /
`CONVENTIONS.md` in your repo root — the conventions cascade prefers
those over this shipped template.

Categories worth documenting:

- **Forbidden in committed files** — project-specific prohibitions beyond
  emojis (e.g., no AI-generation comments, banned APIs, debug prints).
- **Commit conventions overlay** — trailing footer format, branch-name
  prefix rules, scoping beyond Conventional Commits' basics.
- **Testing policy** — runner, colocation, language-specific rules
  (`pytest` for `*.py`, `go test` for `*.go`, `bats` for shell scripts,
  etc.), integration-over-mocks expectations. Also state whether a
  documented operator runbook that executes or depends on in-tree
  assertion helpers counts as a suite under the colocation rule (the
  template's stance: yes — colocate runbook + auto-runnable harness in
  the same `tests/<name>/` so helpers don't fork, and label each
  entry-point `auto` or `manual` in the suite README so the split stays
  scannable).
- **Workflow idioms** — file-shape rules the squad should flag if
  violated (framework patterns, schema conventions).
- **CI gates** — the commands CI runs so the Implementer can pre-flight
  them before pushing.
