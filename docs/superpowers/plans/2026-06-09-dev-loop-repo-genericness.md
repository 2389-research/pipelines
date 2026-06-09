# dev_loop repo-genericness Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Un-lock `dev_loop/` (PR #42 in 2389-research/pipelines) from a single repo so an operator can run `tracker dev_loop/dev_loop.dip` against any git+GitHub project by editing one config file or setting a handful of env vars.

**Architecture:** `setup_run.sh` becomes the sole config resolver — reads `dev_loop/config/dev_loop.config.yaml` via `mikefarah/yq` v4, applies env > YAML > default precedence, writes the resolved snapshot atomically to `$RUN_DIR/env` and a human-readable `$RUN_DIR/config_resolution.txt`, then publishes `.current_rid`. Downstream scripts inline a 17-line bootstrap that honors `DEV_LOOP_STATE_ROOT` + `DEV_LOOP_RUN_DIR` env overrides and sources the env file. A new `tests/test_helpers.bash` collapses 14 bats files' setup() blocks; a new `tests/test_bootstrap_identical.sh` gate prevents the 22 preambles from diverging silently. The `.dip` workflow + persona prompts don't change beyond two hardcoded URL regexes that must be generalized.

**Tech Stack:** POSIX sh (`dash`), `mikefarah/yq` v4, `jq`, `gh` CLI ≥ 2.0, `git`, `bats-core`, `shellcheck --shell=sh`, ajv-cli, GitHub Actions on `ubuntu-latest`.

**Spec:** [`docs/superpowers/specs/2026-06-09-dev-loop-repo-genericness-design.md`](../specs/2026-06-09-dev-loop-repo-genericness-design.md). Read it before starting; it has the threat model, the wired-knob inventory, and the anti-goals checklist.

---

## File Structure

**CREATE:**
- `dev_loop/tests/test_helpers.bash` — one bats helper function `setup_env`; mirrors `setup_run.sh`'s emit allow-list as the unset list; ~50 lines including 20-line header comment.
- `dev_loop/tests/test_bootstrap_identical.sh` — sh script (not bats) that asserts every downstream script's bootstrap preamble is byte-identical to a reference block extracted from `setup_run.sh`'s file header.

**MODIFY (substantial):**
- `dev_loop/scripts/setup_run.sh` — adds yq+variant probe, YAML resolver, base-branch autodetect, sh_single_quote, atomic env+rid publication, config_resolution.txt, EXIT trap, allow-list constant comment block. From ~156 lines to ~330 lines.
- `dev_loop/README.md` — rewrites opening + Configuration; adds Quick start, What dev_loop does NOT do, Anti-patterns; preserves Notable design choices as `## For workflow authors`. From 172 lines to ~250 lines.

**MODIFY (mechanical):**
- 22 of 23 `dev_loop/scripts/*.sh` (every script except `setup_run.sh`): replace 1-7 lines of hardcoded `DIP_ROOT="…/dip/2389-research-pipelines"` literal with the §4.4 17-line preamble. Bootstrap-identity gate enforces byte-identity.
- 14 of 16 `dev_loop/tests/*.bats` files containing `2389-research-pipelines`: collapse setup() to `load 'test_helpers'; setup_env; SCRIPT=...`; replace `${XDG_CACHE_HOME}/dip/2389-research-pipelines/...` references with `${DIP_ROOT}/...`.

**MODIFY (targeted):**
- `dev_loop/scripts/create_worktree.sh:59` — `main` → `${BASE_BRANCH:-main}` (sourced via bootstrap).
- `dev_loop/scripts/pre_filter_issues.sh:38-39` — replace literal filter knobs with `yq` reads from YAML.
- `dev_loop/scripts/fetch_open_issues.sh:36-41` — capture gh stderr to `fetch_error.txt`.
- `dev_loop/scripts/init_iter_counter.sh` — bootstrap preamble swap only (max_iters stays hardcoded per §4.6).
- `dev_loop/dev_loop.dip:66` — `^https://github\\.com/2389-research/pipelines/issues/[0-9]+$` → `^https://github\\.com/[^/]+/[^/]+/issues/[0-9]+$`.
- `dev_loop/schemas/selected_issue.schema.json:27` — same URL regex generalization.
- `dev_loop/config/dev_loop.config.yaml` — comment out the `runtime_state_root` value line; built-in default applies.
- `dev_loop/tests/test_setup_run.bats` — fixture-coincidence audit on the 5 slug-tied assertions + add 5 new test cases; extend the existing missing-tools test to include `yq`.
- `dev_loop/tests/test_worktree.bats` — extend with one BASE_BRANCH=develop case (reuses existing git-init pattern).
- `dev_loop/tests/test_pre_filter.bats` — extend with one YAML-knobs case.
- `.github/workflows/dev_loop_smoke.yml` — pinned mikefarah/yq install + variant gate + bootstrap-identity gate + grep gate.

**OUT-OF-REPO:**
- Edit PR #42 body to add `Closes #43` (otherwise auto-close won't fire).
- PR #42 top-level summary comment after the implementation commits land.
- Comment on issue #43 ("will auto-close on merge").
- Comment on issue #45 (scope down: repo-genericness done; executor-compat docs remains open).

---

## Phase 1 — Resolver core in `setup_run.sh`

Phase verify: `bats dev_loop/tests/test_setup_run.bats` (existing 7 cases still pass; new cases pass as they're added).

### Task 1.1: yq prereq check + mikefarah variant probe

**Files:**
- Modify: `dev_loop/scripts/setup_run.sh:115-124` (prereq command loop)
- Test: `dev_loop/tests/test_setup_run.bats:121-148` (existing "missing tools" test)

- [ ] **Step 1: Extend the existing missing-tools bats test to require `yq`.**

Edit `dev_loop/tests/test_setup_run.bats`, the `@test "missing tools route to setup-failed"` block at line 121. Add `yq` to the list of tools the sysbin omits — it's already not in the symlink loop (line 131-138), so just update the comment and assertion text. Update lines 124-128 to mention yq:

```sh
  # Stage a PATH that contains the POSIX utilities setup_run.sh needs for its
  # own work (mkdir, cat, date, printf, ls, find, awk, kill, etc.) but
  # deliberately omits the dev_loop-required commands (gh, jq, git, tracker, yq).
```

- [ ] **Step 2: Add a new bats test for wrong-variant yq.**

Append to `dev_loop/tests/test_setup_run.bats` (place before the final closing brace if there isn't one — bats files don't have one; just append at EOF):

```sh
@test "wrong-variant yq (kislyuk) routes to setup-failed" {
  # Stage a yq shim that mimics kislyuk/yq's --version output (no "mikefarah" string).
  shim="${TMPDIR}/shim"
  mkdir -p "${shim}"
  cat > "${shim}/yq" <<'YQ'
#!/bin/sh
case $1 in
  --version) printf 'yq 3.4.3\n'; exit 0 ;;
  *) exit 1 ;;
esac
YQ
  chmod +x "${shim}/yq"
  PATH="${shim}:${PATH}" run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  rid="$(cat "${XDG_CACHE_HOME}/dip/dev_loop/.current_rid")"
  grep -q "mikefarah" "${XDG_CACHE_HOME}/dip/dev_loop/runs/${rid}/setup_error.txt"
}
```

NOTE: `${XDG_CACHE_HOME}/dip/dev_loop/...` (new slug) — this assertion will fail until Task 3.1 updates the state path. For now, leave it; it'll go red and then green when Phase 3 lands.

- [ ] **Step 3: Run tests to verify they fail.**

```sh
cd /home/clint/code/2389/pipelines
bats dev_loop/tests/test_setup_run.bats -f "wrong-variant" -f "missing tools"
```

Expected: at least the wrong-variant test fails because variant probe isn't in setup_run.sh yet.

- [ ] **Step 4: Add yq prereq + variant probe to setup_run.sh.**

Edit `dev_loop/scripts/setup_run.sh` around line 115-124 (the existing prereq loop). Replace the loop with:

```sh
# Verify prerequisite tooling.
missing=""
for cmd in gh jq git tracker yq; do
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    missing="${missing}${missing:+ }${cmd}"
  fi
done
if [ -n "${missing}" ]; then
  emit_failure "missing required commands: ${missing} (install yq from https://github.com/mikefarah/yq/releases)"
fi

# Probe yq variant. The Python kislyuk/yq and the Go mikefarah/yq diverge in
# syntax; we require mikefarah v4+. The --version output contains the URL.
if ! yq --version 2>&1 | grep -qF 'github.com/mikefarah/yq'; then
  emit_failure "yq must be mikefarah/yq v4+; got: $(yq --version 2>&1) — install from https://github.com/mikefarah/yq/releases"
fi
```

- [ ] **Step 5: Run tests to verify pass.**

```sh
bats dev_loop/tests/test_setup_run.bats -f "missing tools"
```

Expected: PASS (variant test still red because of slug; ok for now).

- [ ] **Step 6: Commit.**

```sh
git add dev_loop/scripts/setup_run.sh dev_loop/tests/test_setup_run.bats
git commit -m "feat(dev_loop): require mikefarah/yq v4 + add prereq variant probe

Adds yq to setup_run.sh's prereq command check and probes the --version
output for the mikefarah URL string. The kislyuk Python yq (what Ubuntu's
apt ships) is incompatible and routes to setup-failed with an install URL.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 1.2: YAML loading + GH_REPO resolution (env > YAML > fail)

**Files:**
- Modify: `dev_loop/scripts/setup_run.sh:147-154` (env file write block)
- Test: `dev_loop/tests/test_setup_run.bats`

- [ ] **Step 1: Write failing bats tests for YAML repo loading + env override + fail-closed.**

Append to `dev_loop/tests/test_setup_run.bats`:

```sh
@test "YAML repo loads when no env override" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${XDG_CACHE_HOME}/dip/dev_loop/.current_rid")"
  grep -q "^GH_REPO='test-org/test-repo'$" \
    "${XDG_CACHE_HOME}/dip/dev_loop/runs/${rid}/env"
  grep -qF "GH_REPO=test-org/test-repo (source=yaml)" \
    "${XDG_CACHE_HOME}/dip/dev_loop/runs/${rid}/config_resolution.txt"
}

@test "env GH_REPO beats YAML" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: yaml-org/yaml-repo
base_branch: main
YAML
  GH_REPO=env-org/env-repo run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${XDG_CACHE_HOME}/dip/dev_loop/.current_rid")"
  grep -q "^GH_REPO='env-org/env-repo'$" \
    "${XDG_CACHE_HOME}/dip/dev_loop/runs/${rid}/env"
  grep -qF "GH_REPO=env-org/env-repo (source=env)" \
    "${XDG_CACHE_HOME}/dip/dev_loop/runs/${rid}/config_resolution.txt"
}

@test "no repo configured (no env, no YAML) routes to setup-failed" {
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  rid="$(cat "${XDG_CACHE_HOME}/dip/dev_loop/.current_rid")"
  err="${XDG_CACHE_HOME}/dip/dev_loop/runs/${rid}/setup_error.txt"
  grep -q "no repo configured" "${err}"
  grep -q "GH_REPO" "${err}"
  grep -q "dev_loop.config.yaml" "${err}"
}
```

(Slug paths use `dev_loop` not `2389-research-pipelines` per §4.3 — Phase 3 will update other tests but these are new.)

- [ ] **Step 2: Run tests to verify they fail.**

```sh
bats dev_loop/tests/test_setup_run.bats -f "YAML repo loads" -f "env GH_REPO beats" -f "no repo configured"
```

Expected: all 3 fail (YAML not loaded; env file format wrong; slug still `2389-research-pipelines`).

- [ ] **Step 3: Update DIP_ROOT slug + remove the hardcoded GH_REPO env-file write + add YAML resolver.**

Edit `dev_loop/scripts/setup_run.sh`:

1. Change line 19:
```sh
DIP_ROOT="${DEV_LOOP_STATE_ROOT:-${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop}"
```

2. Same change in the resume-detection block (line 25-31) and the lock-dir block (line 73-101): all references to the slug-bearing `DIP_ROOT` already use the variable, so the line-19 change alone propagates.

3. After the yq variant probe (Task 1.1's added code), insert the YAML resolver block. Replace the existing `# GH_REPO lock + per-run identity` block (lines 147-154) with this expanded version:

```sh
# --- YAML config resolver -------------------------------------------------
# Allow-list (canonical home for both setup_run's emit and test_helpers.bash's
# unset list — keep these two in sync):
#   GH_REPO BASE_BRANCH DEV_LOOP_RUN_ID DEV_LOOP_RUN_DIR TRACKER_RUN_DIR
#   ALLOW_NO_CI
# --------------------------------------------------------------------------
CFG="dev_loop/config/dev_loop.config.yaml"
yaml_repo=""
yaml_base_branch=""
yaml_allow_no_ci=""
if [ -f "${CFG}" ]; then
  if ! yaml_repo=$(yq -r '.repo // ""' "${CFG}" 2>"${run_dir}/setup_error.txt"); then
    emit_failure "yq parse failed; see setup_error.txt"
  fi
  yaml_base_branch=$(yq -r '.base_branch // ""' "${CFG}")
  yaml_allow_no_ci=$(yq -r '.allow_no_ci // ""' "${CFG}")
fi

# Reject newline/CR/NUL in any scalar (structural hygiene per spec §3.5).
reject_special() {
  case $1 in
    *"$(printf '\n')"*|*"$(printf '\r')"*|*"$(printf '\0')"*)
      emit_failure "config value contains newline/CR/NUL (key=$2)" ;;
  esac
}
reject_special "${yaml_repo}" repo
reject_special "${yaml_base_branch}" base_branch
reject_special "${yaml_allow_no_ci}" allow_no_ci

# Resolve with precedence env > YAML > default. Track source for the log.
if [ -n "${GH_REPO:-}" ]; then
  resolved_repo="${GH_REPO}"; src_repo=env
elif [ -n "${yaml_repo}" ]; then
  resolved_repo="${yaml_repo}"; src_repo=yaml
else
  emit_failure "no repo configured (set GH_REPO env var or populate ${CFG} with: repo: owner/name)"
fi
```

(`BASE_BRANCH` resolution comes in Task 1.3; `ALLOW_NO_CI` resolution and the env file write come in Task 1.5.)

- [ ] **Step 4: Run tests.**

```sh
bats dev_loop/tests/test_setup_run.bats -f "no repo configured"
```

Expected: the no-repo test PASSES (setup-failed correctly emitted). The "YAML loads" + "env beats YAML" tests still FAIL because env file write hasn't been refactored yet.

- [ ] **Step 5: Commit.**

```sh
git add dev_loop/scripts/setup_run.sh dev_loop/tests/test_setup_run.bats
git commit -m "feat(dev_loop): resolve GH_REPO from YAML/env with fail-closed default

Switches DIP_ROOT's default slug from '2389-research-pipelines' (repo-keyed)
to 'dev_loop' (workflow-keyed) per pipelines#43. Adds an in-memory YAML
resolver that loads dev_loop/config/dev_loop.config.yaml via yq and applies
env > YAML > default precedence for the repo knob. Missing-repo case
fail-closes with a setup-failed marker and a clear error message naming
both the GH_REPO env var and the YAML path.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 1.3: BASE_BRANCH resolution + autodetect via `gh repo view`

**Files:**
- Modify: `dev_loop/scripts/setup_run.sh` (after Task 1.2's resolver)
- Test: `dev_loop/tests/test_setup_run.bats`

- [ ] **Step 1: Write failing bats test for autodetect via gh shim.**

Append:

```sh
@test "BASE_BRANCH autodetect via gh shim" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
YAML
  shim="${TMPDIR}/shim"
  mkdir -p "${shim}"
  # Mock gh repo view to return a non-default branch.
  cat > "${shim}/gh" <<'GH'
#!/bin/sh
case "$1 $2 $3" in
  "repo view --json")
    if printf '%s\n' "$@" | grep -q defaultBranchRef; then
      printf 'develop\n'
      exit 0
    fi ;;
esac
exit 1
GH
  chmod +x "${shim}/gh"
  # Real yq is needed; pass through.
  ln -sf "$(command -v yq)" "${shim}/yq" 2>/dev/null || true
  ln -sf "$(command -v jq)" "${shim}/jq" 2>/dev/null || true
  ln -sf "$(command -v git)" "${shim}/git" 2>/dev/null || true
  ln -sf "$(command -v tracker)" "${shim}/tracker" 2>/dev/null || true
  PATH="${shim}:${PATH}" run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${XDG_CACHE_HOME}/dip/dev_loop/.current_rid")"
  grep -q "^BASE_BRANCH='develop'$" \
    "${XDG_CACHE_HOME}/dip/dev_loop/runs/${rid}/env"
  grep -qF "BASE_BRANCH=develop (source=autodetect)" \
    "${XDG_CACHE_HOME}/dip/dev_loop/runs/${rid}/config_resolution.txt"
}

@test "DEV_LOOP_BASE_BRANCH env beats YAML" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
base_branch: master
YAML
  DEV_LOOP_BASE_BRANCH=feature/foo run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${XDG_CACHE_HOME}/dip/dev_loop/.current_rid")"
  grep -q "^BASE_BRANCH='feature/foo'$" \
    "${XDG_CACHE_HOME}/dip/dev_loop/runs/${rid}/env"
}
```

- [ ] **Step 2: Run tests to verify fail.**

```sh
bats dev_loop/tests/test_setup_run.bats -f "BASE_BRANCH"
```

Expected: both fail.

- [ ] **Step 3: Append BASE_BRANCH resolution to setup_run.sh.**

After the GH_REPO resolution block from Task 1.2:

```sh
# Resolve BASE_BRANCH with precedence env > YAML > autodetect via gh.
if [ -n "${DEV_LOOP_BASE_BRANCH:-}" ]; then
  resolved_base="${DEV_LOOP_BASE_BRANCH}"; src_base=env
elif [ -n "${yaml_base_branch}" ]; then
  resolved_base="${yaml_base_branch}"; src_base=yaml
else
  # Autodetect via gh; timeout caps network hang.
  autodetect=$(timeout 5s gh repo view "${resolved_repo}" \
    --json defaultBranchRef -q .defaultBranchRef.name 2>"${run_dir}/setup_error.txt")
  if [ -z "${autodetect}" ]; then
    emit_failure "base_branch autodetect failed; set DEV_LOOP_BASE_BRANCH or YAML base_branch (gh stderr in setup_error.txt)"
  fi
  resolved_base="${autodetect}"; src_base=autodetect
fi
reject_special "${resolved_base}" base_branch

# Resolve allow_no_ci with precedence env > YAML > "false".
if [ -n "${DEV_LOOP_ALLOW_NO_CI:-}" ]; then
  resolved_allow_no_ci="${DEV_LOOP_ALLOW_NO_CI}"; src_allow=env
elif [ -n "${yaml_allow_no_ci}" ]; then
  resolved_allow_no_ci="${yaml_allow_no_ci}"; src_allow=yaml
else
  resolved_allow_no_ci=false; src_allow=default
fi
```

- [ ] **Step 4: Run tests.**

```sh
bats dev_loop/tests/test_setup_run.bats -f "BASE_BRANCH"
```

Expected: DEV_LOOP_BASE_BRANCH test passes; autodetect test may still fail until Task 1.5 (env file write) lands. Acceptable.

- [ ] **Step 5: Commit.**

```sh
git add dev_loop/scripts/setup_run.sh dev_loop/tests/test_setup_run.bats
git commit -m "feat(dev_loop): resolve BASE_BRANCH with env/YAML/autodetect precedence

Adds env > YAML > 'gh repo view --json defaultBranchRef' autodetect.
The autodetect is wrapped in 'timeout 5s' to cap network hangs and emits
setup-failed with the gh stderr in setup_error.txt when it fails.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 1.4: `sh_single_quote` helper + emit_env

**Files:**
- Modify: `dev_loop/scripts/setup_run.sh` (top of file, alongside other helpers)
- Test: `dev_loop/tests/test_setup_run.bats`

- [ ] **Step 1: Write failing test for shell-safe env file emission.**

Append:

```sh
@test "env file rejects YAML values containing newlines" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  printf 'repo: "test/test"\nbase_branch: "foo\nbar"\n' \
    > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-failed" ]
  rid="$(cat "${XDG_CACHE_HOME}/dip/dev_loop/.current_rid")"
  grep -qi "newline" \
    "${XDG_CACHE_HOME}/dip/dev_loop/runs/${rid}/setup_error.txt"
}

@test "env file single-quotes values containing $(...) and backticks" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: 'test/test'
base_branch: '$(rm -rf $HOME)'
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${XDG_CACHE_HOME}/dip/dev_loop/.current_rid")"
  # Sourcing the env file must NOT execute the substitution.
  ( set -a; . "${XDG_CACHE_HOME}/dip/dev_loop/runs/${rid}/env"; set +a
    [ "${BASE_BRANCH}" = '$(rm -rf $HOME)' ] )
}
```

- [ ] **Step 2: Run tests to verify fail.**

```sh
bats dev_loop/tests/test_setup_run.bats -f "single-quotes" -f "rejects YAML values"
```

Expected: both fail (no env file write yet).

- [ ] **Step 3: Add the `sh_single_quote` and `emit_env` helpers near the top of setup_run.sh, just after the EXIT trap block (around line 60):**

```sh
# Shell-safe single-quote escape for env-file values. The '\''-trick is
# POSIX and works under dash. Rejects newline / CR / NUL upstream.
sh_single_quote() {
  case $1 in
    *"$(printf '\n')"*|*"$(printf '\r')"*|*"$(printf '\0')"*)
      return 1 ;;
  esac
  printf "'%s'\n" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

emit_env() {
  esc=$(sh_single_quote "$2") || {
    emit_failure "env value contains newline/CR/NUL (key=$1)"
  }
  printf '%s=%s' "$1" "${esc}" >&3
}
```

The `>&3` redirect targets a temp env file descriptor opened in Task 1.5; for now this won't work standalone — that's OK, Task 1.5 closes the loop.

- [ ] **Step 4: Defer test run until Task 1.5; commit the helpers.**

```sh
git add dev_loop/scripts/setup_run.sh dev_loop/tests/test_setup_run.bats
git commit -m "feat(dev_loop): add sh_single_quote + emit_env helpers

POSIX single-quote escape for env-file values; rejects newline/CR/NUL
upstream. Used by the resolver to write a shell-safe env file in Task 1.5.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 1.5: Atomic env file write + symlink guard + config_resolution.txt

**Files:**
- Modify: `dev_loop/scripts/setup_run.sh` (replace lines 147-154 — the existing env file write block)
- Test: `dev_loop/tests/test_setup_run.bats`

- [ ] **Step 1: Test for atomic ordering + chmod modes + config_resolution.txt format.**

The previous tasks' tests cover the env file content. Add one more for modes + config_resolution structure:

```sh
@test "atomic env write: env file mode 600, RUN_DIR mode 700, config_resolution.txt format" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
base_branch: main
allow_no_ci: false
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  rid="$(cat "${XDG_CACHE_HOME}/dip/dev_loop/.current_rid")"
  run_dir="${XDG_CACHE_HOME}/dip/dev_loop/runs/${rid}"
  # Mode bits.
  [ "$(stat -c %a "${run_dir}")" = "700" ]
  [ "$(stat -c %a "${run_dir}/env")" = "600" ]
  # config_resolution.txt one line per knob with (source=...) annotation.
  grep -qE '^GH_REPO=test-org/test-repo \(source=yaml\)$' "${run_dir}/config_resolution.txt"
  grep -qE '^BASE_BRANCH=main \(source=yaml\)$' "${run_dir}/config_resolution.txt"
  grep -qE '^ALLOW_NO_CI=false \(source=yaml\)$' "${run_dir}/config_resolution.txt"
}
```

- [ ] **Step 2: Verify failure.**

```sh
bats dev_loop/tests/test_setup_run.bats -f "atomic env write"
```

Expected: FAIL.

- [ ] **Step 3: Replace the env-file write block in setup_run.sh.**

Delete lines 147-154 (the existing block starting with `# GH_REPO lock + per-run identity`). Replace with:

```sh
# Build env file atomically: write to env.tmp inside RUN_DIR, fsync via mv -f.
# umask 077 from line 1 means env.tmp inherits mode 600; chmod is belt-and-braces.
env_tmp="${run_dir}/env.tmp"
exec 3>"${env_tmp}"
emit_env GH_REPO          "${resolved_repo}"
emit_env BASE_BRANCH      "${resolved_base}"
emit_env ALLOW_NO_CI      "${resolved_allow_no_ci}"
emit_env DEV_LOOP_RUN_ID  "${rid}"
emit_env DEV_LOOP_RUN_DIR "${run_dir}"
emit_env TRACKER_RUN_DIR  "${tracker_run_dir}"
# Each emit_env line ends without a trailing newline; printf '\n' between them.
exec 3>&-
chmod 600 "${env_tmp}"
# Reject symlink at destination (the chmod 700 RUN_DIR forecloses cross-UID
# attacks; this is belt-and-braces for accidental operator symlinks).
[ ! -L "${run_dir}/env" ] || emit_failure "${run_dir}/env is a symlink; refusing"
mv -f "${env_tmp}" "${run_dir}/env"

# Write config_resolution.txt — operator-readable line per knob.
cat > "${run_dir}/config_resolution.txt" <<EOF
GH_REPO=${resolved_repo} (source=${src_repo})
BASE_BRANCH=${resolved_base} (source=${src_base})
ALLOW_NO_CI=${resolved_allow_no_ci} (source=${src_allow})
DIP_ROOT=${DIP_ROOT} (source=${DEV_LOOP_STATE_ROOT:+env}${DEV_LOOP_STATE_ROOT:-default})
EOF
chmod 600 "${run_dir}/config_resolution.txt"
```

Also fix the `emit_env` helper from Task 1.4 — change `printf '%s=%s' "$1" "${esc}" >&3` to include a newline between lines:

```sh
emit_env() {
  esc=$(sh_single_quote "$2") || {
    emit_failure "env value contains newline/CR/NUL (key=$1)"
  }
  printf '%s=%s' "$1" "${esc}" >&3
}
```

Wait — `sh_single_quote` already appends `\n` (`printf "'%s'\n" ...`). So the lines are newline-separated automatically. Verify by reading sh_single_quote's printf.

- [ ] **Step 4: Run tests.**

```sh
bats dev_loop/tests/test_setup_run.bats -f "YAML repo loads" -f "env GH_REPO beats" -f "atomic env write" -f "single-quotes"
```

Expected: all PASS.

- [ ] **Step 5: Commit.**

```sh
git add dev_loop/scripts/setup_run.sh dev_loop/tests/test_setup_run.bats
git commit -m "feat(dev_loop): atomic env file write with shell-safe quoting

Writes env.tmp in RUN_DIR then mv -f to env; chmod 600 + umask 077 keep
the file owner-only. emit_env uses sh_single_quote to neutralize \$(...)
and backticks in YAML values — operator-trusted YAML is treated
structurally for hygiene (see spec §3.5). Also writes
config_resolution.txt with one line per knob and (source=env|yaml|
default|autodetect) annotations for debuggability.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 1.6: Atomic `.current_rid` publish + EXIT trap

**Files:**
- Modify: `dev_loop/scripts/setup_run.sh:111` and surrounding (the `.current_rid` write)
- Test: `dev_loop/tests/test_setup_run.bats`

- [ ] **Step 1: Test that .current_rid is published AFTER env file is complete.**

This is hard to test for a race; instead assert post-conditions hold simultaneously:

```sh
@test ".current_rid points at a complete env file (atomic publish)" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${XDG_CACHE_HOME}/dip/dev_loop/.current_rid")"
  run_dir="${XDG_CACHE_HOME}/dip/dev_loop/runs/${rid}"
  # If .current_rid exists, env must exist and be readable.
  [ -f "${run_dir}/env" ]
  [ ! -L "${run_dir}/env" ]
  # No orphan tmp files.
  ! [ -e "${XDG_CACHE_HOME}/dip/dev_loop/.current_rid.tmp" ]
  ! [ -e "${run_dir}/env.tmp" ]
}
```

- [ ] **Step 2: Verify.**

```sh
bats dev_loop/tests/test_setup_run.bats -f "atomic publish"
```

Expected: probably PASS already if Task 1.5 wrote env before `.current_rid`. But the existing code at line 111 writes `.current_rid` BEFORE the env file (line 154). Re-read line 111: `printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid"`. So that's BEFORE the env write — the test should currently FAIL because of a leftover orphan or because of the order.

- [ ] **Step 3: Reorder + add EXIT trap cleanup.**

Edit `dev_loop/scripts/setup_run.sh`:

1. Delete the existing `printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid"` line (line 111).

2. After the config_resolution.txt write (end of Task 1.5's block), add the atomic publish:

```sh
# Publish .current_rid atomically AFTER env + config_resolution are in place.
printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid.tmp"
if ! mv -Tf "${DIP_ROOT}/.current_rid.tmp" "${DIP_ROOT}/.current_rid"; then
  emit_failure "atomic publish of .current_rid failed (mv -Tf returned $?)"
fi
```

3. Extend the EXIT trap (lines 52-58) to unlink orphan .tmp files:

```sh
trap 'rc=$?
      # Unlink any orphan .tmp files from a partial run; harmless when none exist.
      rm -f "${DIP_ROOT}/.current_rid.tmp" 2>/dev/null || true
      [ -n "${run_dir:-}" ] && rm -f "${run_dir}/env.tmp" 2>/dev/null || true
      if [ "${rc}" -ne 0 ]; then
        mkdir -p "${run_dir}" 2>/dev/null || true
        printf "unexpected non-zero exit (rc=%s)\n" "${rc}" \
          > "${run_dir}/setup_error.txt" 2>/dev/null || true
        printf "setup-failed"
        exit 0
      fi' EXIT
```

- [ ] **Step 4: Run tests + the existing 7 tests must still pass.**

```sh
bats dev_loop/tests/test_setup_run.bats
```

Expected: ALL PASS.

- [ ] **Step 5: Commit.**

```sh
git add dev_loop/scripts/setup_run.sh dev_loop/tests/test_setup_run.bats
git commit -m "fix(dev_loop): publish .current_rid atomically after env file complete

Closes the .current_rid TOCTOU window where a downstream script could
read the new rid before the env file was written. New order:
1. Build env in env.tmp under RUN_DIR.
2. chmod 600 + mv -f env.tmp env.
3. Write config_resolution.txt.
4. mv -Tf .current_rid.tmp .current_rid (atomic pointer publish).

EXIT trap unlinks orphan .tmp files on any non-zero exit so a partial
run can't be 'promoted' later by a subsequent invocation.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 1.7: Allow-list drift-guard test (§5.4)

**Files:**
- Test: `dev_loop/tests/test_setup_run.bats`

- [ ] **Step 1: Add a bats case that reads the allow-list constant from setup_run.sh and asserts the env file emits only those keys.**

Append to `dev_loop/tests/test_setup_run.bats`:

```sh
@test "env file emits only allow-listed keys (drift guard vs comment block)" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: test-org/test-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"

  # Read the canonical allow-list from setup_run.sh's comment block.
  # The block is delimited by "Allow-list" header until the next ----- line.
  allow=$(awk '/^# Allow-list/,/^# -+$/' "${SCRIPT}" \
    | tr -d '#' | tr -s ' \n' ' ' | tr ' ' '\n' \
    | grep -E '^[A-Z][A-Z0-9_]+$' | sort -u)
  [ -n "${allow}" ]

  # Every key emitted to env must be in the allow-list.
  emitted=$(awk -F= '/^[A-Z]/ {print $1}' "${DIP_ROOT}/runs/${rid}/env" | sort -u)
  for key in ${emitted}; do
    printf '%s\n' "${allow}" | grep -qx "${key}" \
      || { printf 'env emitted forbidden key: %s\n' "${key}" >&2; return 1; }
  done
}
```

- [ ] **Step 2: Run the test.**

```sh
bats dev_loop/tests/test_setup_run.bats -f "drift guard"
```

Expected: PASS (Task 1.2 already established the comment block; Task 1.5 emits only the listed keys).

- [ ] **Step 3: Commit.**

```sh
git add dev_loop/tests/test_setup_run.bats
git commit -m "test(dev_loop): allow-list drift guard between setup_run comment + emit

The emit allow-list lives as a comment block above emit_env() in
setup_run.sh; this test reads that block and asserts the per-run env
file contains only those keys. Catches the future-contributor drift
where someone adds a wired knob to the emit code but forgets to update
the comment (or vice versa). Single source of truth for both the
helper's unset list and the runtime emitter.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 2 — Bats helper + fixture-coincidence audit

Phase verify: `bats dev_loop/tests/test_setup_run.bats` (all pass with new fixture-based assertions).

### Task 2.1: Create `tests/test_helpers.bash`

**Files:**
- Create: `dev_loop/tests/test_helpers.bash`

- [ ] **Step 1: Write the helper file.**

```sh
# dev_loop/tests/test_helpers.bash — shared bats test fixture helper.
#
# Exports ONE function: setup_env().
#
# Conventions:
# - DIP_ROOT (test-side) is an inspection alias for DEV_LOOP_STATE_ROOT
#   (script-side). Scripts honor DEV_LOOP_STATE_ROOT; tests use DIP_ROOT
#   to assert on staged paths. Both point at the same TMPDIR-anchored dir.
# - The unset list mirrors setup_run.sh's emit allow-list (canonical home is
#   the comment block immediately above emit_env() in scripts/setup_run.sh).
#   When you add an env-honored knob, update BOTH places.
# - HOME and XDG_CONFIG_HOME are sandboxed to TMPDIR so tests don't leak the
#   developer's gh auth into the test environment.
#
# Conventional bats usage:
#   setup() {
#     load 'test_helpers'
#     setup_env
#     SCRIPT="${BATS_TEST_DIRNAME}/../scripts/<name>.sh"
#   }
#   teardown() { rm -rf "${TMPDIR}"; }

setup_env() {
  TMPDIR="$(mktemp -d)"
  export XDG_CACHE_HOME="${TMPDIR}/cache"
  export HOME="${TMPDIR}/home"
  mkdir -p "${HOME}"
  export DEV_LOOP_STATE_ROOT="${TMPDIR}/state"
  DIP_ROOT="${DEV_LOOP_STATE_ROOT}"
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

- [ ] **Step 2: Verify shellcheck-clean.**

```sh
shellcheck --shell=sh dev_loop/tests/test_helpers.bash
```

Expected: 0 issues.

- [ ] **Step 3: Commit.**

```sh
git add dev_loop/tests/test_helpers.bash
git commit -m "test(dev_loop): add shared bats helper (setup_env)

Single source of truth for test env staging: TMPDIR + XDG sandbox +
DEV_LOOP_STATE_ROOT + WORKDIR + .tracker/runs stub. The unset list
mirrors setup_run.sh's emit allow-list so test fixtures don't depend
on the developer's shell having (or not having) GH_REPO / GH_TOKEN /
DEV_LOOP_* env vars.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 2.2: Fixture-coincidence audit of `test_setup_run.bats`

**Files:**
- Modify: `dev_loop/tests/test_setup_run.bats`

- [ ] **Step 1: Identify slug-tied assertions.**

```sh
grep -n "2389-research" dev_loop/tests/test_setup_run.bats
```

You'll find ~16 hits. Each is either (a) a state-path component (`${XDG_CACHE_HOME}/dip/2389-research-pipelines/...`) — fixable mechanically — or (b) a value assertion that would pass coincidentally even after the fix.

Line 27 is the canonical example:
```sh
grep -q "^GH_REPO=2389-research/pipelines$" \
  "${XDG_CACHE_HOME}/dip/2389-research-pipelines/runs/${rid}/env"
```

This passes under the new design only because the shipped YAML's `repo:` field also says `2389-research/pipelines`. The test no longer proves the resolver worked.

- [ ] **Step 2: Rewrite line 27's test to stage a non-default YAML and assert the resolved value matches.**

Replace lines 19-29 (the `@test "first run emits setup-ok and seeds .current_rid"` block) with:

```sh
@test "first run emits setup-ok and seeds .current_rid (from YAML)" {
  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
repo: fixture-org/fixture-repo
base_branch: main
YAML
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "setup-ok" ]
  [ -f "${DIP_ROOT}/.current_rid" ]
  rid="$(cat "${DIP_ROOT}/.current_rid")"
  [ -n "${rid}" ]
  [ -f "${DIP_ROOT}/runs/${rid}/env" ]
  grep -q "^GH_REPO='fixture-org/fixture-repo'$" \
    "${DIP_ROOT}/runs/${rid}/env"
  grep -qF "GH_REPO=fixture-org/fixture-repo (source=yaml)" \
    "${DIP_ROOT}/runs/${rid}/config_resolution.txt"
}
```

- [ ] **Step 3: Update the file's other slug-tied assertions to use `${DIP_ROOT}` from the helper.**

Replace the existing `setup()` block (lines 4-13) with:

```sh
setup() {
  load 'test_helpers'
  setup_env
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/setup_run.sh"
}

teardown() { rm -rf "${TMPDIR}"; }
```

Mechanically replace every `${XDG_CACHE_HOME}/dip/2389-research-pipelines` with `${DIP_ROOT}` throughout the file.

```sh
sed -i 's|\${XDG_CACHE_HOME}/dip/2389-research-pipelines|${DIP_ROOT}|g' dev_loop/tests/test_setup_run.bats
```

- [ ] **Step 4: Run all of test_setup_run.bats.**

```sh
bats dev_loop/tests/test_setup_run.bats
```

Expected: ALL PASS (existing 7 + new from Phase 1).

- [ ] **Step 5: Commit.**

```sh
git add dev_loop/tests/test_setup_run.bats
git commit -m "test(dev_loop): fixture-coincidence audit on test_setup_run.bats

Rewrites the canonical 'first run' test to stage a non-default fixture
YAML ('fixture-org/fixture-repo') and assert the resolved value matches.
Previously the test passed only because the shipped YAML happens to
contain '2389-research/pipelines' — it did not prove the YAML resolver
actually ran. Also collapses setup/teardown to use test_helpers' setup_env
and switches state-path references from the 2389-research-pipelines slug
to the helper's DIP_ROOT.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 3 — 22-script bootstrap rollout

Phase verify: `sh dev_loop/tests/test_bootstrap_identical.sh` + all bats pass.

### Task 3.1: Bootstrap-identity test (red until Task 3.2)

**Files:**
- Create: `dev_loop/tests/test_bootstrap_identical.sh`

- [ ] **Step 1: Write the test.**

```sh
#!/bin/sh
# test_bootstrap_identical.sh — assert every downstream script's bootstrap
# preamble is byte-identical to the canonical reference. Prevents the 22
# inline copies from drifting silently (the cost of POSIX sh + tracker's
# `sh -c "$(cat ...)"` invocation forecloses sharing via `lib/bootstrap.sh`).
#
# Reference block is in scripts/setup_run.sh's file header, between the
# markers `# ---begin-bootstrap-reference---` and `# ---end-bootstrap-reference---`.
# Every script except setup_run.sh itself must inline that block verbatim
# (allowing only the leading shebang to differ).
set -eu

cd "$(dirname "$0")/.."
ref=$(awk '/^# ---begin-bootstrap-reference---$/,/^# ---end-bootstrap-reference---$/' scripts/setup_run.sh)
if [ -z "${ref}" ]; then
  printf 'reference block not found in scripts/setup_run.sh\n' >&2
  exit 1
fi

fail=0
for f in scripts/*.sh; do
  case ${f} in scripts/setup_run.sh) continue ;; esac
  # Extract the inlined block: everything between the same markers in the script.
  block=$(awk '/^# ---begin-bootstrap-reference---$/,/^# ---end-bootstrap-reference---$/' "${f}")
  if [ "${block}" != "${ref}" ]; then
    printf 'bootstrap drift in %s\n' "${f}" >&2
    fail=1
  fi
done
exit ${fail}
```

- [ ] **Step 2: Make it executable + run to verify FAIL.**

```sh
chmod +x dev_loop/tests/test_bootstrap_identical.sh
sh dev_loop/tests/test_bootstrap_identical.sh
```

Expected: FAIL ("reference block not found" — setup_run.sh doesn't have the markers yet).

- [ ] **Step 3: Add the reference markers + bootstrap content to setup_run.sh's header.**

Edit `dev_loop/scripts/setup_run.sh`, after line 17 (`set -eu`), insert:

```sh
# ---begin-bootstrap-reference---
# This is the canonical 17-line bootstrap preamble every other dev_loop script
# inlines verbatim between the same markers. Drift is enforced by
# tests/test_bootstrap_identical.sh. When tracker exports TRACKER_WORKFLOW_DIR
# (pending — see file-header note in setup_run.sh), this collapses to:
#   . "${TRACKER_WORKFLOW_DIR}/scripts/lib/bootstrap.sh"
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
# ---end-bootstrap-reference---
```

NOTE: In `setup_run.sh` itself this block is documentation (between markers, no other consumers). The real `setup_run.sh` does its own state setup via the resolver. The block here is the reference, NOT the runtime path for setup_run.sh.

- [ ] **Step 4: Run the test to verify still FAIL (no other script has the block).**

```sh
sh dev_loop/tests/test_bootstrap_identical.sh
```

Expected: FAIL ("bootstrap drift in scripts/<every-other>.sh").

- [ ] **Step 5: Commit.**

```sh
git add dev_loop/tests/test_bootstrap_identical.sh dev_loop/scripts/setup_run.sh
git commit -m "test(dev_loop): bootstrap-identity gate (red, expected)

Adds tests/test_bootstrap_identical.sh that extracts the canonical
bootstrap block from scripts/setup_run.sh (between begin/end markers)
and asserts every other script in scripts/*.sh inlines the same block
verbatim. Currently RED — Task 3.2 makes it green.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 3.2: Roll out the bootstrap to 22 scripts

**Files:**
- Modify: 22 of 23 files in `dev_loop/scripts/*.sh` (everything except `setup_run.sh`)

- [ ] **Step 1: Extract the reference block to a temp file.**

```sh
awk '/^# ---begin-bootstrap-reference---$/,/^# ---end-bootstrap-reference---$/' \
  dev_loop/scripts/setup_run.sh > /tmp/dev_loop_bootstrap.sh
wc -l /tmp/dev_loop_bootstrap.sh   # should print ~21
```

- [ ] **Step 2: For each of the 22 scripts, replace the existing `DIP_ROOT=...; rid=$(cat ...); RUN_DIR=...` preamble with the reference block.**

The existing preamble varies slightly per script (see `persist_pragmatism_verdict.sh:6-9` vs `cleanup_worktree.sh:9-14` vs `fetch_open_issues.sh:10-15`). The replacement is mechanical: find the existing DIP_ROOT-through-RUN_DIR lines and substitute the block.

Do this in a single multi-script `sed`/`awk` pass. Open each file in the editor and:
1. Find the first occurrence of `DIP_ROOT="${XDG_CACHE_HOME...`.
2. Replace from that line through (including) the next `RUN_DIR="${DIP_ROOT}/runs/${rid}"` line OR the next `mkdir -p "${RUN_DIR}"` line — whichever ends the preamble.
3. Replace with the contents of `/tmp/dev_loop_bootstrap.sh`.

Most scripts also have a separate `set -a; . "${RUN_DIR}/env"; set +a` block (e.g., `recheck_pr_sha.sh:18-23`); delete it (the bootstrap reference already sources the env file).

- [ ] **Step 3: Verify bootstrap identity passes.**

```sh
sh dev_loop/tests/test_bootstrap_identical.sh
```

Expected: PASS (exit 0).

- [ ] **Step 4: Verify shellcheck stays clean.**

```sh
shellcheck --shell=sh dev_loop/scripts/*.sh
```

Expected: 0 issues. (One existing SC1091 disable is inside the bootstrap reference and propagates correctly.)

- [ ] **Step 5: Verify all bats still pass.**

```sh
bats dev_loop/tests/*.bats
```

Expected: ALL PASS. The bats setup() blocks haven't been migrated yet (Task 3.3 does that) but the new bootstrap honors `DEV_LOOP_STATE_ROOT` which the helper exports.

- [ ] **Step 6: Commit.**

```sh
git add dev_loop/scripts/
git commit -m "refactor(dev_loop): inline canonical bootstrap preamble in 22 scripts

Every script except setup_run.sh now inlines the same 17-line bootstrap
between '# ---begin-bootstrap-reference---' and the matching end marker.
The block: resolves DIP_ROOT from DEV_LOOP_STATE_ROOT or the workflow-keyed
default; resolves RUN_DIR from DEV_LOOP_RUN_DIR override or .current_rid;
sources \$RUN_DIR/env after refusing to source a symlinked env.

Replaces 23 hardcoded 'DIP_ROOT=\${XDG_CACHE_HOME...}/dip/2389-research-pipelines'
literals. Replaces 8 'export GH_REPO=\"\${GH_REPO:-2389-research/pipelines}\"'
fallbacks (GH_REPO now flows from the env file).

Bootstrap identity is enforced by tests/test_bootstrap_identical.sh.

Closes pipelines#43.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 3.3: Migrate 14 bats files to the helper

**Files:**
- Modify: 14 bats files containing the slug.

- [ ] **Step 1: List the affected files.**

```sh
grep -l '2389-research-pipelines' dev_loop/tests/*.bats
```

Should print 14 file paths.

- [ ] **Step 2: For each file, replace the inline setup/teardown with `load 'test_helpers'; setup_env` and the slug-bearing paths with `${DIP_ROOT}`.**

Mechanical edits per file:

```sh
# Replace the setup() block. Each file's setup() looks like:
#   setup() {
#     DIP_ROOT="${XDG_CACHE_HOME}/dip/2389-research-pipelines"
#     ... mkdir -p "${DIP_ROOT}/runs" ...
#   }
# Replace with:
#   setup() {
#     load 'test_helpers'
#     setup_env
#     SCRIPT="${BATS_TEST_DIRNAME}/../scripts/<this-script-name>.sh"
#   }
#   teardown() { rm -rf "${TMPDIR}"; }
```

Then replace all `${XDG_CACHE_HOME}/dip/2389-research-pipelines` with `${DIP_ROOT}`:

```sh
for f in $(grep -l '2389-research-pipelines' dev_loop/tests/*.bats); do
  sed -i 's|\${XDG_CACHE_HOME}/dip/2389-research-pipelines|${DIP_ROOT}|g' "${f}"
done
```

Inspect each file by hand to make sure no logic broke. Some bats have additional `mkdir -p "${DIP_ROOT}/runs/${rid}"` calls — those stay; only the `DIP_ROOT=...` definition gets removed.

- [ ] **Step 3: Verify shellcheck on bats wrappers if any (most bats don't get linted; check existing pattern).**

- [ ] **Step 4: Run all bats.**

```sh
bats dev_loop/tests/*.bats
```

Expected: ALL PASS (85 existing + new ones from Phase 1 and 2).

- [ ] **Step 5: Commit.**

```sh
git add dev_loop/tests/
git commit -m "test(dev_loop): migrate 14 bats files to shared test_helpers

Each affected bats file's setup() collapses to 'load test_helpers;
setup_env; SCRIPT=...' and slug-bearing path references switch to the
helper's \${DIP_ROOT}. Future state-path changes are now a 1-file edit
(tests/test_helpers.bash) instead of a 14-file cascade.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 4 — Wired knobs

Phase verify: `bats dev_loop/tests/test_worktree.bats dev_loop/tests/test_pre_filter.bats dev_loop/tests/test_fetch_open_issues.bats`.

### Task 4.1: `create_worktree.sh` uses `BASE_BRANCH` from env

**Files:**
- Modify: `dev_loop/scripts/create_worktree.sh:59`
- Test: `dev_loop/tests/test_worktree.bats`

- [ ] **Step 1: Add a new bats test for `BASE_BRANCH=develop`.**

Append to `dev_loop/tests/test_worktree.bats`:

```sh
@test "BASE_BRANCH from env drives create_worktree (no main branch)" {
  # Stage a fixture repo with a 'develop' branch but no 'main'.
  cd "${WORKDIR}"
  git init -q -b develop "${WORKDIR}/upstream"
  cd "${WORKDIR}/upstream"
  git config user.email t@t
  git config user.name t
  printf 'seed\n' > README.md
  git add README.md
  git commit -q -m seed
  cd "${WORKDIR}"
  # Clone the develop-only repo into the worktree fixture.
  git clone -q "${WORKDIR}/upstream" "${WORKDIR}/work"
  cd "${WORKDIR}/work"
  # Stage a minimal RUN_DIR with env containing BASE_BRANCH=develop.
  rid="rid-$$"
  mkdir -p "${DIP_ROOT}/runs/${rid}"
  cat > "${DIP_ROOT}/runs/${rid}/env" <<EOF
GH_REPO='test/test'
BASE_BRANCH='develop'
ALLOW_NO_CI='false'
DEV_LOOP_RUN_ID='${rid}'
DEV_LOOP_RUN_DIR='${DIP_ROOT}/runs/${rid}'
TRACKER_RUN_DIR='${WORKDIR}/.tracker/runs/trk-$$'
EOF
  chmod 600 "${DIP_ROOT}/runs/${rid}/env"
  printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid"
  printf 'feat/test-branch' > "${DIP_ROOT}/runs/${rid}/branch_name.txt"
  printf '999' > "${DIP_ROOT}/runs/${rid}/selected_issue_number.txt"
  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/create_worktree.sh"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  [ "${output}" = "worktree-ok" ]
  # The worktree must have been created off 'develop', not 'main'.
  worktree_path="$(cat "${DIP_ROOT}/runs/${rid}/worktree.path")"
  ( cd "${worktree_path}"
    [ "$(git rev-parse --abbrev-ref HEAD)" = "feat/test-branch" ]
    # The branch base should resolve to develop (the only branch in upstream).
    git rev-parse develop >/dev/null 2>&1 )
}
```

- [ ] **Step 2: Verify fail.**

```sh
bats dev_loop/tests/test_worktree.bats -f "BASE_BRANCH from env"
```

Expected: FAIL (script hardcodes `main`).

- [ ] **Step 3: Edit `dev_loop/scripts/create_worktree.sh:59`. Replace the literal `main` with `${BASE_BRANCH:-main}`.**

Change line 59 from:
```sh
  git worktree add -b "${branch}" "${worktree_path}" main \
```
to:
```sh
  git worktree add -b "${branch}" "${worktree_path}" "${BASE_BRANCH:-main}" \
```

`BASE_BRANCH` is sourced via the bootstrap preamble (Task 3.2) which sources `$RUN_DIR/env`.

- [ ] **Step 4: Run the new test + the existing test_worktree.bats cases.**

```sh
bats dev_loop/tests/test_worktree.bats
```

Expected: ALL PASS.

- [ ] **Step 5: Commit.**

```sh
git add dev_loop/scripts/create_worktree.sh dev_loop/tests/test_worktree.bats
git commit -m "feat(dev_loop): create_worktree honors BASE_BRANCH from env

Replaces literal 'main' at create_worktree.sh:59 with \${BASE_BRANCH:-main}
sourced from the per-run env file. New bats case stages a develop-only
fixture repo and asserts the worktree branches off develop.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 4.2: `pre_filter_issues.sh` reads filter knobs from YAML

**Files:**
- Modify: `dev_loop/scripts/pre_filter_issues.sh:38-39`
- Test: `dev_loop/tests/test_pre_filter.bats`

- [ ] **Step 1: Add a bats case asserting custom YAML filter knobs are honored.**

Append to `dev_loop/tests/test_pre_filter.bats`:

```sh
@test "YAML excluded_labels override filters out custom labels" {
  rid="rid-$$"
  mkdir -p "${DIP_ROOT}/runs/${rid}"
  cat > "${DIP_ROOT}/runs/${rid}/env" <<EOF
GH_REPO='test/test'
BASE_BRANCH='main'
ALLOW_NO_CI='false'
DEV_LOOP_RUN_ID='${rid}'
DEV_LOOP_RUN_DIR='${DIP_ROOT}/runs/${rid}'
TRACKER_RUN_DIR='${WORKDIR}/.tracker/runs/trk-$$'
EOF
  chmod 600 "${DIP_ROOT}/runs/${rid}/env"
  printf '%s' "${rid}" > "${DIP_ROOT}/.current_rid"

  mkdir -p "${WORKDIR}/dev_loop/config"
  cat > "${WORKDIR}/dev_loop/config/dev_loop.config.yaml" <<'YAML'
issue_filter:
  excluded_labels: ["wontfix"]
  excluded_title_regex: "(?i)WIP:"
YAML

  cat > "${DIP_ROOT}/runs/${rid}/issues.json" <<'JSON'
[
  {"number":1,"title":"keep me","url":"https://github.com/test/test/issues/1","labels":[{"name":"P1"}],"author":{"login":"a"},"createdAt":"2026-06-01T00:00:00Z","body":""},
  {"number":2,"title":"WIP: skip","url":"https://github.com/test/test/issues/2","labels":[{"name":"P1"}],"author":{"login":"a"},"createdAt":"2026-06-01T00:00:00Z","body":""},
  {"number":3,"title":"label skip","url":"https://github.com/test/test/issues/3","labels":[{"name":"wontfix"}],"author":{"login":"a"},"createdAt":"2026-06-01T00:00:00Z","body":""}
]
JSON

  SCRIPT="${BATS_TEST_DIRNAME}/../scripts/pre_filter_issues.sh"
  run sh -c "$(cat "${SCRIPT}")"
  [ "${status}" -eq 0 ]
  count=$(cat "${DIP_ROOT}/runs/${rid}/filter_count.txt")
  [ "${count}" = "1" ]
  jq -e '.[0].number == 1' "${DIP_ROOT}/runs/${rid}/filtered_issues.json"
}
```

- [ ] **Step 2: Verify fail.**

```sh
bats dev_loop/tests/test_pre_filter.bats -f "YAML excluded_labels"
```

Expected: FAIL (script hardcodes filter knobs).

- [ ] **Step 3: Replace `pre_filter_issues.sh:37-42`.**

Delete the hardcoded `EXCLUDED_LABELS='[…]'` and `EXCLUDED_TITLE_RE='(…)'` literals. Replace with:

```sh
# Filter knobs: read directly from YAML (no env round-trip) per spec §4.6.
CFG="dev_loop/config/dev_loop.config.yaml"
if [ -f "${CFG}" ]; then
  EXCLUDED_LABELS=$(yq -o=json '.issue_filter.excluded_labels // ["survey","question","tracking","blocked"]' "${CFG}")
  EXCLUDED_TITLE_RE=$(yq -r '.issue_filter.excluded_title_regex // "(dev_loop|dippin meta|tracker meta)"' "${CFG}")
else
  EXCLUDED_LABELS='["survey","question","tracking","blocked"]'
  EXCLUDED_TITLE_RE='(dev_loop|dippin meta|tracker meta)'
fi
```

- [ ] **Step 4: Verify all of test_pre_filter.bats.**

```sh
bats dev_loop/tests/test_pre_filter.bats
```

Expected: ALL PASS.

- [ ] **Step 5: Commit.**

```sh
git add dev_loop/scripts/pre_filter_issues.sh dev_loop/tests/test_pre_filter.bats
git commit -m "feat(dev_loop): pre_filter reads filter knobs from YAML

Replaces hardcoded EXCLUDED_LABELS + EXCLUDED_TITLE_RE in
pre_filter_issues.sh with yq reads against dev_loop/config/dev_loop.config.yaml.
Defaults preserve current behavior when the YAML omits the keys.
Direct-from-YAML chosen over env-file round-trip (deviation from mission
item #6) to avoid JSON-array escape-quoting risk for two simple knobs —
documented in spec §4.6.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 4.3: `fetch_open_issues.sh` captures gh stderr

**Files:**
- Modify: `dev_loop/scripts/fetch_open_issues.sh:36-41`

- [ ] **Step 1: Edit the gh invocation to capture stderr.**

In `dev_loop/scripts/fetch_open_issues.sh`, find the existing `gh issue list` call (around line 36). Change:

```sh
gh issue list \
  --state open \
  --json number,title,url,labels,author,createdAt,body \
  --limit 200 \
  > "${RUN_DIR}/issues.json" \
  || emit_failure "gh issue list failed"
```

to:

```sh
if ! gh issue list \
    --state open \
    --json number,title,url,labels,author,createdAt,body \
    --limit 200 \
    > "${RUN_DIR}/issues.json" \
    2> "${RUN_DIR}/fetch_error.txt"; then
  err=$(head -c 500 "${RUN_DIR}/fetch_error.txt" 2>/dev/null)
  emit_failure "gh issue list failed for ${GH_REPO}: ${err}"
fi
```

- [ ] **Step 2: Verify existing test_fetch_open_issues.bats still passes.**

```sh
bats dev_loop/tests/test_fetch_open_issues.bats
```

Expected: PASS (the stderr capture is additive; no behavioral test change required).

- [ ] **Step 3: Commit.**

```sh
git add dev_loop/scripts/fetch_open_issues.sh
git commit -m "fix(dev_loop): capture gh stderr in fetch_open_issues failure path

When gh issue list fails (no access, SSO refresh required, wrong repo
name), the operator previously saw only 'gh issue list failed'. Now
captures gh's stderr to fetch_error.txt and includes the first 500 chars
in the setup_error message so the operator sees the actual gh diagnostic.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 5 — URL pattern generalization

Phase verify: `dippin check dev_loop/dev_loop.dip && tracker validate dev_loop/dev_loop.dip && ajv validate -s dev_loop/schemas/selected_issue.schema.json -d dev_loop/tests/fixtures/selected_issue_sample.json`.

### Task 5.1: Generalize the SelectedIssue URL regex

**Files:**
- Modify: `dev_loop/dev_loop.dip:66`
- Modify: `dev_loop/schemas/selected_issue.schema.json:27`

- [ ] **Step 1: Edit both files.**

`dev_loop/dev_loop.dip:66`:
```
- "url": {"type": "string", "pattern": "^https://github\\.com/2389-research/pipelines/issues/[0-9]+$"},
+ "url": {"type": "string", "pattern": "^https://github\\.com/[^/]+/[^/]+/issues/[0-9]+$"},
```

`dev_loop/schemas/selected_issue.schema.json:27`:
```
- "pattern": "^https://github\\.com/2389-research/pipelines/issues/[0-9]+$"
+ "pattern": "^https://github\\.com/[^/]+/[^/]+/issues/[0-9]+$"
```

- [ ] **Step 2: Verify gates.**

```sh
dippin check dev_loop/dev_loop.dip
tracker validate dev_loop/dev_loop.dip
ajv validate --strict=false -s dev_loop/schemas/selected_issue.schema.json \
  -d dev_loop/tests/fixtures/selected_issue_sample.json
```

Expected: all green. The fixture's URL is `https://github.com/2389-research/pipelines/issues/42` which matches the broader pattern.

- [ ] **Step 3: Commit.**

```sh
git add dev_loop/dev_loop.dip dev_loop/schemas/selected_issue.schema.json
git commit -m "feat(dev_loop): generalize SelectedIssue URL pattern for any GitHub repo

dev_loop.dip:66 and schemas/selected_issue.schema.json:27 both pinned
the SelectedIssue URL regex to '2389-research/pipelines' — selector
outputs from any other repo would have failed schema validation and
routed to CleanupWorktree. Generalized to '[^/]+/[^/]+' (owner/name).

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

---

## Phase 6 — README + CI + housekeeping

Phase verify: rendered README visually + dev_loop_smoke.yml CI run green.

### Task 6.1: Rewrite README per spec §6.1

**Files:**
- Modify: `dev_loop/README.md`

- [ ] **Step 1: Read the spec's §6.1 table and §4.6's wired-knobs table.**

```sh
sed -n '200,260p' docs/superpowers/specs/2026-06-09-dev-loop-repo-genericness-design.md
```

Per the table, the edits are:
1. Replace L3-L7 opening line with the audience-neutral one.
2. Insert new `## Quick start` section between "What it does" (current L9-L28) and "Prerequisites" (current L30).
3. Extend Prerequisites with a fenced mikefarah-vs-kislyuk callout block.
4. Rewrite `## Configuration` (current L68-L82): delete "v1 does not load YAML" prose, add precedence paragraph, add 4-row env-var table, name the unused YAML keys (`priority_label_order`, `excluded_author_globs`, `local_test_command`), one sentence on `config_resolution.txt`.
5. Extend `## Failure modes` (current L84-L101) with one sentence on new categories.
6. Add `## What dev_loop does NOT do` section.
7. Add `## Anti-patterns` section.
8. Add disclosure line in Configuration: "Implementer's pre-push gate commands (`dippin check`, `tracker validate`, `bats`) are currently pipelines-specific."
9. Move "Notable design choices vs issue #40 v6" (L113-L136) to a `## For workflow authors` subsection at the end.
10. Update Layout section to mention `runs/<rid>/env`, `runs/<rid>/config_resolution.txt`.

- [ ] **Step 2: Make the edits.**

(See spec §6.1 for the exact replacement table; each row has the new text inline.)

The 4-row env-var table:

```markdown
| Env var | YAML key | Default | What it does |
|---|---|---|---|
| `GH_REPO` | `repo` | — (setup-failed if absent) | Target GitHub repo as `owner/name`. |
| `DEV_LOOP_BASE_BRANCH` | `base_branch` | autodetect via `gh repo view` | Branch to base PRs from. |
| `DEV_LOOP_STATE_ROOT` | `runtime_state_root` | `${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop` | Per-run state dir. |
| `DEV_LOOP_ALLOW_NO_CI` | `allow_no_ci` | `false` | Merge when no CI is configured. |

Precedence: env > YAML > default. Verify resolution via `runs/<rid>/config_resolution.txt`.

The YAML carries three additional keys that are NOT wired in v1:
`priority_label_order` (the jq priority function does its own normalize-and-rank
for P0..P3), `excluded_author_globs` (filter hardcodes the `[bot]` check), and
`local_test_command` (reserved for a future repo-level smoke check the
implementer must pass before pushing).
```

- [ ] **Step 3: Verify visually.**

```sh
glow dev_loop/README.md   # or cat / less
```

- [ ] **Step 4: Commit.**

```sh
git add dev_loop/README.md
git commit -m "docs(dev_loop): rewrite README for cross-repo support

Replaces the '2389-research/pipelines'-pinned opening with an
audience-neutral framing. Adds:
- Quick start with the YAML edit + env-var override recipes.
- yq mikefarah-vs-kislyuk fenced callout in Prerequisites.
- 4-row env-var reference table + precedence note + config_resolution.txt
  pointer in Configuration.
- 'What dev_loop does NOT do' (scope boundary).
- 'Anti-patterns' (secret leak vs prompt-injection distinguished).
- Disclosure that Implementer's pre-push gates are pipelines-specific.
Moves 'Notable design choices vs issue #40 v6' to a 'For workflow
authors' subsection.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 6.2: Update CI workflow

**Files:**
- Modify: `.github/workflows/dev_loop_smoke.yml`

- [ ] **Step 1: Add pinned mikefarah/yq install + variant gate.**

In the workflow file, find the `apt-get install` step (around line 36). After it, add:

```yaml
      - name: Install mikefarah/yq v4.44.3
        run: |
          set -eu
          YQ_VER=v4.44.3
          YQ_SHA=2820dc7c5e91d957d9d859d27c1bd1f5f48283b18a40bb8d7d57b13c3b2e6e8c  # update on bump
          curl -fsSL -o /tmp/yq "https://github.com/mikefarah/yq/releases/download/${YQ_VER}/yq_linux_amd64"
          echo "${YQ_SHA}  /tmp/yq" | sha256sum -c -
          sudo mv /tmp/yq /usr/local/bin/yq
          sudo chmod +x /usr/local/bin/yq
          yq --version 2>&1 | grep -qF 'github.com/mikefarah/yq' || { echo "wrong yq variant"; exit 1; }
```

(The `YQ_SHA` placeholder: compute via `sha256sum yq_linux_amd64` after downloading from GitHub Releases at the pinned tag. The current value is a placeholder; the implementer must replace it with the actual SHA-256 of v4.44.3's `yq_linux_amd64` asset.)

- [ ] **Step 2: Add a bootstrap-identity gate step.**

After the existing shellcheck step:

```yaml
      - name: Bootstrap identity gate
        run: sh dev_loop/tests/test_bootstrap_identical.sh
```

- [ ] **Step 3: Add a slug grep gate step.**

```yaml
      - name: Repo-slug grep gate
        run: |
          set -eu
          # Allowed slug locations: YAML default + repo_conventions.md (operator template) + fixtures.
          hits=$(grep -rln '2389-research-pipelines\|2389-research/pipelines' dev_loop/ \
            | grep -v -E '^dev_loop/(config/dev_loop\.config\.yaml|config/repo_conventions\.md|tests/fixtures/)$' || true)
          if [ -n "${hits}" ]; then
            printf 'Repo-slug leaked outside allowed locations:\n%s\n' "${hits}" >&2
            exit 1
          fi
```

- [ ] **Step 4: Trigger the workflow via push or `act` locally; verify all gates pass.**

- [ ] **Step 5: Commit.**

```sh
git add .github/workflows/dev_loop_smoke.yml
git commit -m "ci(dev_loop): install pinned mikefarah/yq + add bootstrap + slug gates

- Install mikefarah/yq v4.44.3 with sha256 verification and a variant
  probe (--version must contain 'github.com/mikefarah/yq').
- New bootstrap-identity gate runs tests/test_bootstrap_identical.sh.
- New slug grep gate fails the build if '2389-research/pipelines' or
  '2389-research-pipelines' leaks outside the YAML default, repo
  conventions template, or test fixtures.

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>"
```

### Task 6.3: PR + issue housekeeping (out-of-repo)

**Files:** N/A (GitHub UI / `gh` CLI work).

- [ ] **Step 1: Edit PR #42's body to add `Closes #43` alongside the existing `Closes #40`.**

```sh
gh pr view 42 --repo 2389-research/pipelines --json body --jq .body > /tmp/pr42-body.md
# Manually edit /tmp/pr42-body.md to add "Closes #43" to the top, then:
gh pr edit 42 --repo 2389-research/pipelines --body-file /tmp/pr42-body.md
```

- [ ] **Step 2: Post the top-level summary comment on PR #42.**

```sh
gh pr comment 42 --repo 2389-research/pipelines --body "$(cat <<'EOF'
## Revision: cross-repo support

Mid-review, the repo owner flagged that the implementation locked the runtime to `2389-research/pipelines` in ~30 places — dev_loop is meant to run on any git+GitHub project. Fixed in the commits since round 13: YAML config is now loaded at runtime, env-var overrides honored (env > YAML > default), the default state path is workflow-keyed (`dev_loop`, not the repo name), base branch auto-detected via `gh repo view`, `repo_conventions.md` documented as operator-edit-in-place. The 22 inline script bootstraps are enforced byte-identical by `tests/test_bootstrap_identical.sh`. Closes pipelines#43.

Out of scope (separate issues): executor decoupling (pipelines#44); the upstream tracker primitives we'd like to use (tracker#323 and three more tracked in spec §9: workdir concurrency lock, TRACKER_RESUMING, dippin-lang env-prop RFC).

See README.md's new Quick start + Configuration sections.
EOF
)"
```

- [ ] **Step 3: Comment on #43.**

```sh
gh issue comment 43 --repo 2389-research/pipelines --body "Addressed by PR #42; will auto-close on merge (PR body now contains \`Closes #43\`)."
```

- [ ] **Step 4: Comment on #45.**

```sh
gh issue comment 45 --repo 2389-research/pipelines --body "Update: PR #42 covers the cross-repo-support docs (README rewrite, env-var table, Quick start, repo_conventions.md operator-edit workflow). The executor-compat docs piece this issue called for is contingent on pipelines#44 (executor decoupling) landing and remains open."
```

- [ ] **Step 5: Watch CI run on the PR.**

```sh
gh pr checks 42 --repo 2389-research/pipelines --watch
```

Expected: all 9 gates + the new bootstrap-identity + slug-grep gates pass.

- [ ] **Step 6 (no commit — these are GitHub-side actions).**

---

## Phase 7 — Final verification

Run every validation gate from spec §8 before declaring done.

- [ ] **Step 1: All 9 CI gates + new gates locally.**

```sh
cd /home/clint/code/2389/pipelines

dippin check dev_loop/dev_loop.dip
dippin doctor dev_loop/dev_loop.dip
dippin simulate dev_loop/dev_loop.dip
tracker validate dev_loop/dev_loop.dip
shellcheck --shell=sh dev_loop/scripts/*.sh dev_loop/tests/test_helpers.bash dev_loop/tests/test_*.sh
bats dev_loop/tests/*.bats
sh dev_loop/tests/test_marker_coverage.sh
sh dev_loop/tests/test_branch_model_ids.sh
sh dev_loop/tests/test_bootstrap_identical.sh
ajv validate --strict=false -s dev_loop/schemas/selected_issue.schema.json \
  -d dev_loop/tests/fixtures/selected_issue_sample.json
```

Expected: all green.

- [ ] **Step 2: Slug grep gates.**

```sh
grep -rln '2389-research/pipelines' dev_loop/ \
  | grep -v -E '^dev_loop/(config/dev_loop\.config\.yaml|config/repo_conventions\.md|tests/fixtures/)$'
```

Expected: no output (anything printed is a leak).

```sh
grep -rln '2389-research-pipelines' dev_loop/ \
  | grep -v -E '^dev_loop/config/repo_conventions\.md$'
```

Expected: no output.

- [ ] **Step 3: Mode-bit assertion (post-run).**

```sh
tracker dev_loop/dev_loop.dip  # against this repo
rid=$(cat "${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop/.current_rid")
run_dir="${XDG_CACHE_HOME:-${HOME}/.cache}/dip/dev_loop/runs/${rid}"
[ "$(stat -c %a "${run_dir}")" = "700" ]
[ "$(stat -c %a "${run_dir}/env")" = "600" ]
cat "${run_dir}/config_resolution.txt"
```

- [ ] **Step 4: Manual cross-repo smoke test.**

In a separate clone of any GitHub repo (e.g., a personal sandbox):
```sh
cd ~/code/your-sandbox-repo
cp -r ~/code/2389/pipelines/dev_loop ./dev_loop
cp dev_loop/config/repo_conventions.md ./dev_loop/config/repo_conventions.md.bak
$EDITOR dev_loop/config/dev_loop.config.yaml   # change repo: to your-org/your-repo
tracker dev_loop/dev_loop.dip
```

Watch the workflow execute; verify it operates on your repo, not on 2389-research/pipelines.

- [ ] **Step 5: Final commit (if any verification fixes needed).**

If everything is green: no commit. If fixes needed: commit and re-run from Step 1.

- [ ] **Step 6: Tag the work as ready for merge.**

```sh
gh pr ready 42 --repo 2389-research/pipelines   # if PR is in draft
```

---

## Anti-goals checklist (re-read before declaring done)

From spec §10:

- [ ] `grep -r '2389-research/pipelines' dev_loop/` returns only YAML default + `repo_conventions.md` + fixtures. (CI gate covers this.)
- [ ] `grep -r '2389-research-pipelines' dev_loop/` returns only `repo_conventions.md`. (CI gate covers this.)
- [ ] README no longer says "v1 is locked to one repo".
- [ ] No new Python / Node deps; no wrapper CLI; no runtime YAML schema validator.
- [ ] Persona prompts, schemas (other than URL regex), workflow node shape untouched.
- [ ] Diff ≤ ~600 lines excluding new tests.
- [ ] 85 existing bats unchanged or mechanically updated (no behavior rewrites).
- [ ] No separate CONTRIBUTING.md.
- [ ] `repo_conventions.md` not renamed.
- [ ] `tests/test_bootstrap_identical.sh` passes — 22 preambles byte-identical.
- [ ] `setup-ok` emits on its own line — no trailing same-line content.

When every checkbox is ticked, the PR is ready for re-review and merge.
