# dev_loop repo-genericness — design spec

**Date:** 2026-06-09  
**PR:** [2389-research/pipelines#42](https://github.com/2389-research/pipelines/pull/42)  
**Branch:** `feat/40-dev-loop`  
**Closes:** pipelines#43 (and scopes down pipelines#45).  
**Out of scope:** pipelines#44 (executor decoupling).

## 1. Problem

`dev_loop/` shipped as an autonomous PR-review-squad loop intended to run on any git+GitHub project. The implementation locked the runtime to `2389-research/pipelines`:

- **23 POSIX-sh scripts** under `dev_loop/scripts/` hardcode `DIP_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/2389-research-pipelines"`.
- **7 scripts** have `${GH_REPO:-2389-research/pipelines}` fallback; `setup_run.sh:150` literally writes `GH_REPO=2389-research/pipelines` to the per-run env file.
- `create_worktree.sh:59` hardcodes `main` as the base branch.
- `init_iter_counter.sh:31` hardcodes `max_iters=5`.
- `pre_filter_issues.sh:38-39` hardcodes filter knobs.
- `dev_loop.dip:66` and `dev_loop/schemas/selected_issue.schema.json:27` hardcode the issue-URL regex to `^https://github\.com/2389-research/pipelines/issues/[0-9]+$` — a different operator's selector output would fail schema validation.
- `dev_loop/config/dev_loop.config.yaml` carries the knobs but is never loaded at runtime (README says so verbatim).
- **14 bats files** independently encode the same hardcoded state path.

The `.dip` workflow shape, persona prompts, and the squad routing are already generic. The repo lock is concentrated in the script layer + two hardcoded URL regexes.

## 2. Goals

- An operator with any git+GitHub repo can run `tracker dev_loop/dev_loop.dip` after editing one config file OR setting a handful of env vars.
- One well-shaped bug fix. No new dependencies beyond `mikefarah/yq`. No new schemas, no wrapper CLI, no runtime YAML schema validator.
- 9 CI gates stay green: `dippin check`/`doctor`/`simulate`, `tracker validate`, `shellcheck --shell=sh`, `bats`, marker coverage, branch model IDs, `ajv`.
- 85 existing bats stay green (mechanical updates only).

## 3. Non-goals

- **Executor decoupling.** `TRACKER_RUN_DIR`, `.tracker/runs/` discovery, `tracker validate` calls stay as-is. That's pipelines#44.
- **Cross-engine support.** Tracker remains the only executor in v1.
- **Language parameterization of Implementer gates.** `implementer.system.md:20` references `dippin check`, `tracker validate`, `bats` — pipelines-specific. README discloses this; we do not refactor it.
- **Persona prompts, workflow node shape, JSON schemas (other than the URL regex) DO NOT CHANGE.**
- **Diff target:** ~600 lines excluding new tests.

## 3.5 Threat model

- **Operator UID is trusted.** Same-UID compromise is out of scope; we do not defend against an attacker who can already write as the operator. This explicitly includes the `.current_rid` content — a same-UID attacker could poison it. The fix to that attack is "don't share the operator's UID", not script-level validation.
- **Other POSIX UIDs on shared CI runners are untrusted.** Defended by `umask 077` + chmod 700 on `$DIP_ROOT` and `$RUN_DIR` + chmod 600 on the env file. Concrete scenario: self-hosted CI runner where dev_loop and another workflow run as different POSIX UIDs.
- **YAML and `repo_conventions.md` are operator-authored** (trusted intent) but treated **structurally** on emit: `sh_single_quote` POSIX `'\''` escape, newline/CR/NUL rejection. Goal is structural hygiene against typos / clipboard paste / accidental content — not adversary defense.
- **`${ctx.last_response}` prompt injection** via malicious contributor to `repo_conventions.md` is a known cross-node risk inherited from dippin (see MEMORY.md `dippin-agent-node-safety`). Mitigation is PR review of `repo_conventions.md` changes; not runtime sanitization. README anti-pattern callout distinguishes this from accidental secret-leak (which is a different threat with different mitigation).

## 4. Design decisions

### 4.1 Centralized YAML→env resolver in `setup_run.sh`

`setup_run.sh` becomes the sole config resolver. It reads `dev_loop/config/dev_loop.config.yaml` once via `mikefarah/yq` v4, resolves each knob with precedence `env > YAML > built-in default`, writes the resolved snapshot atomically to `$RUN_DIR/env` BEFORE publishing `.current_rid`.

Rejected: per-script yq (22× duplication); shared `lib/bootstrap.sh` (tracker's `sh -c "$(cat ...)"` invocation forecloses `$0`-based discovery until `TRACKER_WORKFLOW_DIR` lands).

### 4.2 YAML interpolation: literal-only

YAML scalars are literal strings (no `${VAR}` interpolation). Shipped YAML's `runtime_state_root` becomes optional/commented; the built-in default applies when absent. No `eval` surface.

### 4.3 Workflow-keyed state path

```
$DEV_LOOP_STATE_ROOT                                          (env override)
$YAML.runtime_state_root/dev_loop                             (YAML, +slug)
${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop                (built-in)
```

The slug `dev_loop` (workflow name), not the repo name.

### 4.4 Inline script bootstrap (23 scripts)

Each downstream script (22 of 23 — setup_run.sh itself is the resolver, not a consumer) inlines this preamble, *extending* the existing 3-line `set -a; . "${RUN_DIR}/env"; set +a` pattern (see `persist_pragmatism_verdict.sh:22-26`) with override env vars + symlink guard:

```sh
#!/bin/sh
# Inline bootstrap. See dev_loop/scripts/setup_run.sh's file header for the
# rationale and the upstream-issue tracking that would let this collapse to
# `. "${TRACKER_WORKFLOW_DIR}/scripts/lib/bootstrap.sh"` when tracker exports it.
set -eu

STATE_ROOT_DEFAULT="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop"
DIP_ROOT="${DEV_LOOP_STATE_ROOT:-${STATE_ROOT_DEFAULT}}"

if [ -n "${DEV_LOOP_RUN_DIR:-}" ]; then
  RUN_DIR="${DEV_LOOP_RUN_DIR}"
else
  rid=$(cat "${DIP_ROOT}/.current_rid" 2>/dev/null || true)
  [ -n "${rid}" ] || { printf 'no .current_rid; was setup_run executed?\n' >&2; exit 1; }
  RUN_DIR="${DIP_ROOT}/runs/${rid}"
fi

[ -f "${RUN_DIR}/env" ] || { printf 'missing env at %s\n' "${RUN_DIR}/env" >&2; exit 1; }
[ ! -L "${RUN_DIR}/env" ] || { printf 'env is a symlink; refusing\n' >&2; exit 1; }

set -a
# shellcheck disable=SC1091  # runtime path; resolves only after setup_run executes
. "${RUN_DIR}/env"
set +a
```

The duplication is acceptable because: (a) tracker's `sh -c "$(cat ...)"` forecloses sharing without `TRACKER_WORKFLOW_DIR` (filed upstream — Section 9); (b) per-script marker emit + exit semantics on missing rid are intentionally per-script (not duplication); (c) under the threat model (§3.5), `.current_rid` content is operator-trusted, so the cut helper-pattern's rid-traversal validation is intentionally absent here.

**Drift guard:** `dev_loop/tests/test_bootstrap_identical.sh` (new) asserts every script's preamble is byte-identical from the shebang through `set +a`. Prevents the first refactor PR from diverging the 22 copies silently.

### 4.5 Bats helper

`dev_loop/tests/test_helpers.bash` exports ONE function:

```sh
setup_env() {
  TMPDIR="$(mktemp -d)"
  export XDG_CACHE_HOME="${TMPDIR}/cache"
  export HOME="${TMPDIR}/home"
  mkdir -p "${HOME}"
  export DEV_LOOP_STATE_ROOT="${TMPDIR}/state"
  DIP_ROOT="${DEV_LOOP_STATE_ROOT}"   # test inspection alias
  unset GH_REPO GH_HOST GH_TOKEN GITHUB_TOKEN \
        GH_CONFIG_DIR XDG_CONFIG_HOME \
        DEV_LOOP_BASE_BRANCH DEV_LOOP_ALLOW_NO_CI DEV_LOOP_RUN_DIR \
        DEV_LOOP_CI_POLL_INTERVAL DEV_LOOP_CI_POLL_TIMEOUT
  WORKDIR="${TMPDIR}/workdir"
  mkdir -p "${WORKDIR}/.tracker/runs/trk-$$"
  cd "${WORKDIR}"
  mkdir -p "${DIP_ROOT}/runs"
}
```

The unset list **mirrors** the emit allow-list (§5.4). Single source of truth lives as a constant comment block above `emit_env()` in `setup_run.sh` (canonical home); both this helper and the allow-list test read it.

### 4.6 Wired knobs (exhaustive)

| Knob | env var | YAML key | Default | Failure mode |
|---|---|---|---|---|
| repo | `GH_REPO` | `repo` | — | setup-failed: "no repo configured" |
| base_branch | `DEV_LOOP_BASE_BRANCH` | `base_branch` | autodetect via `gh repo view --json defaultBranchRef -q .defaultBranchRef.name` (5s timeout) | setup-failed if autodetect AND both inputs missing |
| state_root | `DEV_LOOP_STATE_ROOT` | `runtime_state_root` | `${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop` | mkdir -p natural failure |
| allow_no_ci | `DEV_LOOP_ALLOW_NO_CI` | `allow_no_ci` | `false` | (no failure path) |

Direct-from-YAML via yq in `pre_filter_issues.sh` (no env round-trip — mission item #6 deviation, intentional because JSON-array round-trip through KEY=VALUE env adds escape-quoting risk for two simple knobs):
- `issue_filter.excluded_labels` (default `["survey","question","tracking","blocked"]`)
- `issue_filter.excluded_title_regex` (default `(dev_loop|dippin meta|tracker meta)`)

Bootstrap-only:
- `DEV_LOOP_RUN_DIR` — env-only; lets executor/test harness bypass `.current_rid` lookup.

**Explicit cuts** (each documented as not-wired so future contributors don't hunt):
- `max_iters` — mission item #7. CUT runtime env override. Hardcoded `5` stays in `init_iter_counter.sh` AND `.dip` `defaults max_restarts:`. Reasoning: the env override syncs only one of three layers (`.dip` defaults stays hardcoded), so it gives operators false confidence. Operators wanting non-5 edit both layers explicitly.
- `priority_label_order` / `excluded_author_globs` — `pre_filter`'s jq does its own normalize-and-rank; wiring requires a jq rewrite.
- `local_test_command` — YAML comment says "reserved for future use".

`init_iter_counter.sh` is still touched (preamble swap per §4.4), just not for max_iters wiring.

### 4.7 Failure-mode design — `setup_run.sh` flow

```
1.  set -eu; umask 077
2.  Resume detection (existing logic; if prior worktree, emit setup-resume-required, exit)
3.  Concurrency lock (existing logic)
4.  Prereq commands: gh, jq, git, tracker, yq (mikefarah install hint in error)
5.  YAML parse via yq (stderr → setup_error.txt on failure)
6.  Resolve knobs in memory (env > YAML > default):
       BASE_BRANCH falls through to `timeout 5s gh repo view --json defaultBranchRef ...`
7.  Reject newline / CR / NUL in any scalar going to env file
8.  Discover tracker artifact dir (existing logic)
9.  mkdir -p $RUN_DIR (mode 700 from umask)
10. Build $RUN_DIR/env.tmp using sh_single_quote helper for every value
11. [ ! -L "${RUN_DIR}/env" ] guard
12. mv -f $RUN_DIR/env.tmp $RUN_DIR/env  (atomic same-fs rename; chmod 600 already from umask)
13. Write $RUN_DIR/config_resolution.txt — exact line format:
       <KEY>=<value> (source=<yaml|env|default|autodetect>)
       One key per line; same key order as the env-file allow-list.
14. mv -Tf $DIP_ROOT/.current_rid.tmp $DIP_ROOT/.current_rid
       If mv fails (cross-fs, EACCES): emit_failure with the mv stderr.
       Old .current_rid stays in place; downstream resolves to the prior run cleanly.
15. printf 'setup-ok\n'                  (stdout: marker line ONLY; trailing newline)
       Resolved-config summary is written to config_resolution.txt — NOT stdout.
       Existing `[ "${output}" = "setup-ok" ]` assertions and tracker's
       anchored marker_grep stay safe.
16. EXIT trap throughout: unlink orphan $DIP_ROOT/.current_rid.tmp and $RUN_DIR/env.tmp
       SIGKILL bypasses the trap; orphans are clutter not vector (next setup_run
       overwrites .current_rid.tmp with `>`; env.tmp is inside RUN_DIR which is
       per-run so cross-run collision is impossible).
```

**Atomic ordering:** env complete BEFORE `.current_rid` publish. Downstream sees consistent `{rid, env}` or nothing.

**Shell injection:** `sh_single_quote` uses POSIX `'\''` idiom; reject newline (NL via `printf`, not literal `\n`) / CR / NUL upstream at step 7. Operator-trusted YAML treated structurally.

**Privilege channel:** `umask 077` early; chmod is inherited (no explicit chmod-after-mv races). Comment in setup_run.sh names the threat (§3.5).

**Empathy:** `fetch_open_issues.sh` gets a one-line stderr capture fix (`2> "${RUN_DIR}/fetch_error.txt"`); when GH_REPO is inaccessible, the operator sees gh's actual error text instead of "gh issue list failed". This replaces the pre-flight `gh repo view` check.

### 4.8 Resume semantics

When `setup-resume-required` fires (prior worktree detected), the operator runs `tracker --resume <rid>`. Resumed runs trust the frozen `$RUN_DIR/env` — no YAML re-read, no hash compare. If the operator edited YAML between runs, the resumed run uses the OLD values; cleanup-and-fresh-start is the documented recovery path.

### 4.9 `repo_conventions.md` handling

Keep the canonical filename. Scripts (`fetch_pr_context.sh:77`, `init_iter_counter.sh:40`, `inc_iter_counter.sh:39`) keep reading at the hardcoded relative path. **Do not genericize content.** The existing 2389-pipelines file content IS the template — operators edit in place for their project's conventions. README documents this explicitly with a WHY paragraph distinguishing accidental-secret-leak from prompt-injection threats.

Section 8's grep gate **explicitly allows `repo_conventions.md` content as exception** for the slug match (preserves CI's ability to run dev_loop against this repo).

## 5. Test architecture

### 5.1 One helper file

Already specified in §4.5 (full function body). 20-line header comment in the file documents purpose, the `DIP_ROOT` vs `DEV_LOOP_STATE_ROOT` distinction, the unset-list/emit-allow-list mirror, and points at `setup_run.sh`'s allow-list constant as canonical.

### 5.2 Mechanical bats rewrites

All 14 bats files containing the slug: setup() collapses to `load 'test_helpers'; setup_env; SCRIPT=...`. Every assertion line referencing `${XDG_CACHE_HOME}/dip/2389-research-pipelines/...` switches to `${DIP_ROOT}/...`. ~75 lines deleted across the suite.

### 5.3 New bats cases

1. YAML repo (non-default `test-org/test-repo`) loads + asserts `(source=yaml)` in config_resolution.txt.
2. Env GH_REPO beats YAML + asserts `(source=env)`.
3. `DEV_LOOP_STATE_ROOT` override.
4. `BASE_BRANCH=develop` drives create_worktree (extend test_worktree.bats; reuse git-init pattern).
5. `BASE_BRANCH` autodetect via gh shim + asserts `(source=autodetect)`.
6. YAML filter knobs honored (per §4.6 direct-from-YAML path; pre_filter still sources env for `DIP_ROOT`/`RUN_DIR` via its bootstrap preamble, plus yq-reads `dev_loop/config/dev_loop.config.yaml` for filter knobs).
7. Fail-closed when no repo (assert stable substrings: `no repo configured`, `GH_REPO`, `dev_loop.config.yaml`).
8. Malformed YAML → setup-failed with yq stderr in setup_error.txt.

Extend `test_setup_run.bats:121` to add `yq` to the omitted-commands list. No separate missing-yq test.

### 5.4 Allow-list test

The emit allow-list constant lives as a **comment block** immediately above `emit_env()` in `setup_run.sh`. The test in `test_setup_run.bats` reads the same constant and asserts the env file contains only those keys. The test catches drift between the documented constant and the runtime keys actually emitted — a documentation-vs-code regression guard. (No separate runtime refusal in `emit_env` — the test alone is sufficient.)

### 5.5 Fixture-coincidence audit

Every existing bats test that asserted `GH_REPO=2389-research/pipelines` (notably `test_setup_run.bats:27`) gets rewritten to stage a YAML with a non-default value and assert the env file contains *that*. Without this audit, "85 tests still pass" is uninformative.

### 5.6 CI workflow

- Install pinned `mikefarah/yq` v4.44.3 via curl + sha256 verification.
- Gate step: `yq --version 2>&1 | grep -qF 'github.com/mikefarah/yq' || exit 1`.
- Add the `test_bootstrap_identical.sh` gate (§4.4 drift guard).
- Add the Section 8 grep gate as a CI step (one bash line; cheap insurance).
- No e2e shim test (~150 lines saved; existing PATH-shim pattern in bats covers the same surface).
- Existing `# shellcheck disable=SC1091` directives stay in `dev_loop/scripts/` — the new bootstrap preamble carries the same disable (already inlined in §4.4's code).

## 6. Docs

### 6.1 README — single artifact (no CONTRIBUTING.md)

| Change | Detail |
|---|---|
| Opening line | "dev_loop is an autonomous, issue-driven PR loop you can point at any GitHub repository (any language). Configured today for `tracker` as the executor; engine-pluggability deferred to pipelines#44." |
| NEW `## Quick start` | cd target repo root → drop dev_loop/ in (clone+cp+rm OR tarball) → edit `repo_conventions.md` (with WHY paragraph) → configure via YAML edit OR env vars (show the 2-3 lines to touch) → run from repo root → verify via `cat $XDG_CACHE_HOME/dip/dev_loop/runs/$(cat $XDG_CACHE_HOME/dip/dev_loop/.current_rid)/config_resolution.txt` |
| Prerequisites | Add fenced `mikefarah vs kislyuk` yq footgun callout with install commands |
| Rewrite `## Configuration` | Delete "v1 does not load YAML" prose; precedence paragraph; **4-row env-var table** (GH_REPO, DEV_LOOP_BASE_BRANCH, DEV_LOOP_STATE_ROOT, DEV_LOOP_ALLOW_NO_CI); pointer to YAML for full inventory; one paragraph naming the unused YAML keys (`priority_label_order`, `excluded_author_globs`, `local_test_command`) and why; one sentence on `config_resolution.txt`'s location and format |
| Extend `## Failure modes` | One sentence: "Setup failures write actionable reasons to `runs/<rid>/setup_error.txt`; tail it. Common new categories: invalid YAML, missing yq, GH_REPO not accessible, base-branch autodetect failure, no repo configured." |
| NEW `## What dev_loop does NOT do` | Branch-protection bypass; CODEOWNERS; self-review; test-authoring beyond plan; secret rotation |
| NEW `## Anti-patterns` | (a) Don't commit secrets to `repo_conventions.md` (accidental leak); (b) Don't accept PRs that edit `repo_conventions.md` without review — `${ctx.last_response}` is a prompt-injection vector (separate from a; different mitigation); (c) Don't set `allow_no_ci: true` with branch protection; (d) Don't run dev_loop on a repo with auto-merge enabled; (e) Don't set `DEV_LOOP_STATE_ROOT` to a network mount |
| Disclosure in Configuration | "Implementer's pre-push gate commands (`dippin check`, `tracker validate`, `bats`) are currently pipelines-specific." |
| Update Layout | Mention `runs/<rid>/env`, `config_resolution.txt` (one place) |
| Notable design choices vs #40 v6 | Stays in README under `## For workflow authors` subsection |

### 6.2 PR #42 update

Top-level summary comment, posted after implementation commits land. **AND** edit PR #42's body to add `Closes #43` (the current body has only `Closes #40`; GitHub's auto-close needs the explicit `Closes #43` reference to fire on merge).

### 6.3 Plan doc

`docs/superpowers/plans/2026-06-05-issue-40-dev-loop.md` §12 left untouched. Archival = leave alone.

### 6.4 Issue housekeeping

- **#43**: comment "will auto-close on PR #42 merge" (auto-close requires §6.2's body edit).
- **#45**: comment scoping (repo-genericness done; executor-compat docs remains open).
- **#44**: untouched.

## 7. Implementation surface

Recommended sequencing phases (each phase has its own verify command):

**Phase 1 — Resolver core** | verify: `bats dev_loop/tests/test_setup_run.bats`
- `scripts/setup_run.sh`: resolver flow per §4.7; `sh_single_quote` helper; atomic env+rid; chmod via umask; pre-resolve validation; `config_resolution.txt`; emit allow-list constant + `emit_env()`; EXIT trap.
- `config/dev_loop.config.yaml`: comment out `runtime_state_root` value (built-in default applies).

**Phase 2 — Bats helper + fixture-coincidence audit** | verify: `bats dev_loop/tests/test_setup_run.bats` + new helper file shellcheck-clean
- `tests/test_helpers.bash`: NEW one-function helper per §4.5 + 20-line header comment.
- `tests/test_setup_run.bats`: rewrite line 27's literal assertion + 4 other slug-tied assertions to use non-default fixture YAML; assert `(source=...)` in config_resolution.txt.

**Phase 3 — 22-script bootstrap rollout** | verify: `sh dev_loop/tests/test_bootstrap_identical.sh` + `bats dev_loop/tests/*.bats`
- All 22 downstream scripts (every `dev_loop/scripts/*.sh` except `setup_run.sh`): replace `DIP_ROOT="…/dip/2389-research-pipelines"` literal with the §4.4 preamble.
- 14 bats files: mechanical setup() collapse to `load 'test_helpers'; setup_env`.
- NEW `tests/test_bootstrap_identical.sh`: diff first N lines of every script against `setup_run.sh`'s reference comment block.

**Phase 4 — Wired knobs** | verify: per-knob bats case
- `scripts/create_worktree.sh:59`: replace literal `main` with `${BASE_BRANCH:-main}` from sourced env.
- `scripts/pre_filter_issues.sh:38-39`: replace literal filter knobs with `yq -o=json '.issue_filter.excluded_labels // […]' "$CFG"` + scalar version for the regex.
- `scripts/fetch_open_issues.sh`: one-line stderr-capture fix.
- `tests/test_setup_run.bats` + `test_worktree.bats` + `test_pre_filter.bats`: add the 8 new cases per §5.3.

**Phase 5 — URL-pattern degeneration** | verify: `dippin check && tracker validate`
- `dev_loop.dip:66`: generalize URL regex to `^https://github\\.com/[^/]+/[^/]+/issues/[0-9]+$`.
- `schemas/selected_issue.schema.json:27`: same generalization.
- `tests/fixtures/issues_sample.json`: stays as 2389-pipelines sample data (no change).

**Phase 6 — README + CI + housekeeping** | verify: rendered README sanity + CI workflow runs green
- `README.md`: per §6.1.
- `.github/workflows/dev_loop_smoke.yml`: pinned mikefarah/yq install + variant gate + grep gate + bootstrap-identity gate.
- PR #42 body edit (`Closes #43`); top-level summary comment; issue #43 + #45 comments.

## 8. Validation gates

Beyond the 9 CI gates and the new bootstrap-identity + grep gates:

- `grep -r '2389-research/pipelines' dev_loop/` returns only the YAML default in `dev_loop.config.yaml` + `dev_loop/config/repo_conventions.md` (the existing 2389-pipelines content stays as template) + fixture URLs in `dev_loop/tests/fixtures/`. **No other hits.**
- `grep -r '2389-research-pipelines' dev_loop/` returns only `dev_loop/config/repo_conventions.md` (intentional, per §4.9).
- `$RUN_DIR/env` is mode 600; `$RUN_DIR` and `$DIP_ROOT` are mode 700.
- `$RUN_DIR/config_resolution.txt` shape matches §4.7 step 13.
- Bats fixture-coincidence audit: tests stage non-default values and assert source.
- One manual run against a non-2389 GitHub repo proves end-to-end.

## 9. Upstream tracker primitives — to file separately from this PR

Concrete issue titles + Plan B per ask. Filing sequence: wait for tracker#323 engagement (filed 2026-06-08, no comments yet) before filing more — validates maintainer responsiveness.

| # | Title | Plan B if upstream rejects |
|---|---|---|
| Already filed | tracker#323: `engine: expose run identity to tool subprocesses via TRACKER_RUN_ID / TRACKER_RUN_DIR env vars` | Current `.tracker/runs` ls-discovery fallback stays. |
| File 2nd | tracker: `engine: opt-in .dip directive `concurrency: single` for workdir-level exclusive runs` (issue body MUST include the cross-workflow matrix: 6 of 7 sibling workflows in /home/clint/code/2389/pipelines/ silently corrupt under concurrent runs today; sprint `.ai/ledger.yaml`; iterative `.ai/iter-current-iteration.txt`; build-and-ship `.tracker/fix_count`) | Ship `dev_loop/scripts/dev_loop_run.sh` wrapper with `flock $DIP_ROOT/dev_loop.lock`. |
| File 3rd | tracker: `engine: export TRACKER_RESUMING=1 to tool subprocesses on --resume runs` | Detect via bootstrap heuristic (`[ -f "${RUN_DIR}/env" ] && [ -n "${rid}" ]`). |
| File 4th (lowest priority) | dippin-lang: `RFC: cross-node durable state passing — formalize the .ai/ disk-roundtrip pattern` (must acknowledge `ctx.last_response` exists AND explain why it doesn't solve the durable-multi-field-cross-tool case) | Status quo: every workflow rolls its own disk pattern. |

**Not filed (intentionally):** workflow scratch-dir primitive (B — siblings use durable `.ai/`); `.dip`-level YAML config (C — sprint already does it via yq+sidecar); `TRACKER_WORKFLOW_DIR` discovery (G — purely speculative).

**Per-script comment strategy:** ONE explainer comment block in `setup_run.sh`'s file header documenting (a) the bootstrap pattern rationale, (b) the upstream-issue tracking table. Each other script's bootstrap preamble carries a single line: `# See setup_run.sh header for rationale + upstream tracking`. Avoids 22 places to update when an issue resolves.

## 10. Anti-goals — the fix is wrong if any of these is true at the end

- `grep -r '2389-research/pipelines' dev_loop/` returns hits outside the YAML default + `repo_conventions.md` + fixtures.
- `grep -r '2389-research-pipelines' dev_loop/` returns hits outside `repo_conventions.md`.
- README still tells operators "v1 is locked to one repo".
- New Python / Node deps, wrapper CLI, runtime YAML schema validator.
- Persona prompts, schemas (other than the URL regex), workflow node shape touched.
- Diff exceeds ~600 lines (excluding new tests).
- 85 existing bats deleted or rewritten beyond mechanical updates + the fixture-coincidence audit.
- A separate CONTRIBUTING.md file created.
- `repo_conventions.md` renamed.
- The 22 bootstrap preambles diverge (test_bootstrap_identical.sh would catch this).
- `setup-ok` is emitted with same-line trailing content (anchored marker_grep would break).
