# Review squad: kata board morning-review gate (fix/kata-scripts-by-path, main..HEAD) — 2026-09-18

Panel of seven: workflow (tracker/dippin semantics), recovery, UX, shell, tests, docs, security.
Full reports: review/{workflow,recovery,ux,shell,tests,docs,security}.md. Probe logs: probes/*.log, runs/*.out.
Tracker 0.73.1 (source de15619), Dippin 0.72.0. Every "verified" claim below was reproduced by a reviewer probe or read in tracker source.

Verdict: the design holds (nested runs, ledger, marker routing, restart loop all verified), but two things break the
operator promise: a stopped board never reaches the gate, and a detached board answers its own gate. One injection
vector sits in the pasteable commands of the review.

## CRITICAL (fix before merge)

| # | Issue | Source | Fix (LOC incl. tests/docs) |
|---|-------|--------|----------------------------|
| C1 | Every early stop of run-board.sh exits 1 with no marker: preflight (10-22), lock (28-31), invalid ledger (54), child needing inspection (65-70), stop_board (72-76), three consecutive failures (108-113), bad `kata list` (201), failed report (111/221). Tracker then reports `tool_marker_missing` → "no matching edges", saves NO checkpoint (`engine.go:657-661`), `tracker -r` fails "checkpoint not found", and the stop text plus the `tracker -r <child>` recovery line exist only in `RunBoard/status.json`. The gate never opens for exactly the runs that need a human. | Workflow 1, Recovery 1, UX 3, Shell 1+2, Docs 3, Security 14, Tests G6 | Once a ledger exists, every stop records `stop_reason` (and `stop_child` for an inspection stop), runs the report, prints `board-needs-human`, exits 0. The report prints `Stop reason:` under the header plus `Recover: tracker -r <child> <pipeline>` when a child needs inspection. Exit 1 with no marker stays only for failures before a ledger exists (missing tools, lock, TRACKER_RUN_DIR unset). Tests: every stop case asserts the marker and stop reason; `nested-stop` runs three failures under a real parent and asserts the gate opens with the stop reason in its prompt. ~70 |
| C2 | Closed stdin, `nohup`, `< /dev/null`, and `--auto-approve` answer the gate with Done and the run exits 0 as success (`interviewer_console.go:54-60`, `human.go:104-112`). README 82-83, CHANGELOG 208-209, gotchas 106 and the session memory claim it fails. | Docs 1, Tests 1, Recovery 2, Workflow 3, Security 4, UX 4 | Drop `default: done`: EOF and a blank line then fail the gate ("no input received"/"invalid choice") with a checkpoint, and `tracker -r` from a terminal re-opens it (verified for invalid choice). `--auto-approve` still picks the first choice, Done; document it as the explicit unattended mode. Test `nested-gate-eof`. Fix README, CHANGELOG, gotchas, memory. ~60 |
| C3 | Labels `[D] Done` / `[S] Sweep again` advertise inputs (`d`, `s`, `done`, `sweep`) that the console rejects with "invalid choice" → pipeline_failed; only a number, blank, or the exact label match (`matchConsoleChoice`). `Enter choice [done]` names a non-option, no `*` default marker, README 233 says "choose `Sweep again`". | UX 1, 5; Workflow 4, 12; Docs 6 | Labels `Done` / `Sweep again`; prompt says pick by number (piped stdin) or arrow keys (terminal); README lists accepted inputs. ~15 |
| C4 | In a terminal (the documented tmux setup) the gate is an arrow-key modal (`tui/modal.go`), Escape resolves to the first choice (Done), and a review taller than the window keeps only its last lines. Nothing documents this; the docs describe only the piped-stdin list. | Workflow 2, Docs 2 | Document both surfaces; when clipped, run `board-report <id>` from another shell. ~15 |
| C5 | board-report 72-77 splices `qualified_id`, `base_commit`, `branch` from the agent-written `handoff.json` into pasteable commands. Demo: branch `$(id > /tmp/PWNED-branch)` renders into `git diff …` for the operator to paste. `pr_url` from the child is likewise unvalidated. | Security 3, 13 | Validate at render: commits 40 or 64 hex, branch and qualified id from a conservative charset, https GitHub PR URL; refuse the whole report otherwise with a pointer to the record. ~30 |
| C6 | Under piped stdin tracker reflows the prompt (`PromptPlain`: `strings.Fields` per line, wrap at 76): indentation vanishes, the 79-char `answer` line and the 100+-char review rows wrap, the `next` command lines lose their nesting. `nested-gate` asserts only the `Needs review (1)` heading, so this is invisible to the suite. | UX 2, 11, 14; Workflow 11; Tests 6; Shell 15 | Reflow-proof layout: `- ` item rows, one short second line per item (branch, base, wip, run), short base in `git diff`, every interpolated field newline-flattened; decision rows get the same second line (UX 12). Test asserts a kata row and the intact `answer` command in the `gate_opened.gate_prompt` event. ~40 |

## IMPORTANT (should fix; ★ = do now, cheap)

| # | Issue | Source | Fix |
|---|-------|--------|-----|
| ★I1 | Trap sends SIGTERM (`kill "$child_pid"`) to the child tracker, which handles only SIGINT: no checkpoint flush, agent grandchild orphaned, stale `child.pid`. | Recovery 3, Workflow 5 | `kill -INT`, `wait`, `rm -f child.pid`. ~25 |
| ★I2 | A `completed`/`failed` ledger entry with null `issue_uid` is dropped from the review; `any(...; .issue_uid == $uid)` with null can yield a false `board-clean`. | Shell 3 | Validate uid for non-empty kinds in both readers. ~12 |
| ★I3 | 79 bare `jq -e … >/dev/null` assertions in board.sh fail with exit 1 and no message. | Tests 2, Shell 12 | `|| fail 'label'` on each. ~80, mechanical |
| I4 | Suite isolation: global git hooks fire (`roborev enqueue` per fixture commit, `llm` in prepare-commit-msg), tracker loads `~/.config/tracker/.env` and workdir `.env`, update check hits the network, ~95 run dirs per suite under `~/.local/state/tracker/runs` (2093 dirs, 2.0 GB now). | Tests 3 | `kata/tests/isolate.sh` (HOME, XDG_CONFIG_HOME, XDG_STATE_HOME, TRACKER_NO_UPDATE_CHECK=1, GIT_CONFIG_GLOBAL=fixture with init.defaultBranch, identity) sourced by every test. ~30 |
| ★I5 | `nested` and `nested-failure` inherit the suite's stdin; nothing proves a clean board skips the gate. | Tests 4 | `</dev/null` and assert no `gate_opened`. ~4 |
| ★I6 | Untested: more than one Sweep again, three-failure stop under a parent, EOF, `--auto-approve`, restart budget. | Tests 5, Workflow 14 | `nested-gate` with two sweeps, `nested-stop`, `nested-gate-eof`, `nested-auto-approve`. ~50 |
| ★I7 | `kata/check` simulate greps (`MorningReview`, `"restart":true`) prove node names, not edges. | Workflow 6, Tests 7 | grep the three edge triples, with messages. ~8 |
| ★I8 | The 51st Sweep again fails the run ("max restarts (50) exceeded", Resume block); the budget never resets; board.dip:9 comment undersells it. | Docs 4, Workflow 7, UX 21 | One doc sentence + comment. ~3 |
| ★I9 | `expect_marker` reads merged stdout+stderr and the literal last line, so a stderr line after the marker or a stop path is misjudged. | Shell 4, 5 | Split streams; assert the last marker-shaped stdout line. ~8 |
| I10 | A clean board ends silently: tool stdout is invisible without the TUI, so the night's completions are never shown. | UX 6 | Design call: an acknowledge gate on clean boards, or leave `board-report` as the answer. DEFER to Doctor Biz. |
| I11 | Report node failure halts the run with the error swallowed (resumable with `-r`); the review is computed twice per sweep. | UX 7, 24; Workflow 8 | Document `-r`. Keep. ~2 |
| ★I12 | `kata/answer`: wrong ref exits silently with kata's code (92); success prints only Owner/Labels. | UX 8, 9 | Message on unknown ref; `Released <id>` line. ~16 |
| I13 | Terminology drift: "review" means three things; "Board complete" printed after "Board incomplete" (run-board.sh 209/219); runner vs controller; "sweep" undefined; answer usage says "next board run". | UX 13, Docs 9, 10 | Rename the final controller line; README glossary sentence; answer usage. ~10 |
| I14 | README 107-110 promises controller output that tracker discards without the TUI. | Docs 3 | Folded into C1 docs. |
| I15 | `TRACKER_PASS_ENV=1` in `<workspace>/.env` (agent-writable, or already present) disables tracker's secret filter for every tool command; `.env` files persist across sweeps. | Security 2 | Flag to tracker; README trust paragraph. DEFER code (refusing to claim when `.env` exists would break ordinary repos). |
| I16 | A handoff the operator resolves by hand (closes the kata) stays under Needs review forever; the gate reopens every sweep. | Recovery 5 | Drop closed katas from needs_* and let run-board.sh read `board-report --json` for the count (single source). ~15. Backlog unless hit. |

## MINOR (backlog; ★ = one-liners done in the same pass)

| # | Issue | Source |
|---|-------|--------|
| ★M1 | EXIT trap `rmdir "$lock"` clobbers the exit status when the dir is not empty; use `rm -rf "$lock"`. | Shell 6 |
| ★M2 | HUP/INT/TERM traps in board-report, kata/check, board.sh, tool-commands.sh, github-setup.sh, report.sh clean up but do not re-raise/exit 130. | Shell 7 |
| ★M3 | `pwd` without `-P` in kata/check:6 and tool-commands.sh:5; `cd` without `--`/CDPATH guard in board-report:23. | Shell 8, Security 12 |
| ★M4 | run-board.sh is mode 644 while siblings are 755 and it demands `-x` on board-report. | Shell 9 |
| ★M5 | `|| true` on the grep pipeline in tool-commands.sh:25 masks a bad pattern. | Shell 10 |
| ★M6 | `board-report -h` and `answer -h` fall into the arity error. | UX 15, 16; Docs 15 |
| ★M7 | board-report and answer outside a git repo print git's raw error. | UX 19 |
| ★M8 | Stop reason is the last line of the review, after Remaining open. | UX 20 |
| ★M9 | Only `question` is newline-flattened; branch/qualified id/pr_url can carry newlines into the layout. | Shell 14, Security 9 |
| ★M10 | BOARD-PLAN.md still lists every box ticked with no gate; PLAN.md:15,122 lacks the `.kata.toml`-on-base precondition. | Docs 11 |
| ★M11 | CHANGELOG entry omits the doc changes; gotchas 75-83 entry lacks a heading; README 208 says the board holds unconditionally. | Docs 12, 13, 16 |
| ★M12 | Missing TRACKER_RUN_DIR prints a raw `set -u` diagnostic. | UX 18 |
| M13 | Per-run lock: two boards on one workspace can interleave. | Recovery 4, Security 15 |
| M14 | Newest-by-mtime ledger selection when no id is given. | Recovery 6, Tests 11 |
| M15 | No gate timeout; a forgotten gate holds the 168h run. | Recovery 7 |
| M16 | Two log-parsing idioms in board.sh (with/without `sub`). | Shell 11, Tests 10 |
| M17 | Workflow dir with a space untested; prompt's answer path unquoted. | Shell 13 |
| M18 | Report node has no `output_limit` (attribute exists: node_config.go:424). | Shell 15 |
| M19 | Exit codes undocumented in usage text. | UX 17 |
| M20 | Exit label "Board finished" never renders. | UX 22 |
| M21 | Bell/notification on gate open. | UX 25 |
| M22 | Stray Enter possibly consumed (suspected, not probed). | UX 26 |
| M23 | Clean-board condition and blocked.json removal undocumented. | Docs 7, 8 |
| M24 | Per-target restart wording in README. | Docs 14 |
| M25 | Prose rewrites README 77-84, 129, 132-133; CHANGELOG 202-209. | Docs 18 |
| M26 | board-report's run-id check weaker than run-board.sh's 12-hex. | Security 16 |
| M27 | Lazy run dir: a child killed in its first node leaves no run dir to resume. | Workflow 10 |
| M28 | Ctrl-C at the gate: SIGINT during a modal. | Workflow 9 |
| M29 | board-report error branches untested (G7 ~25 LOC). | Tests 8 |
| M30 | Fixture fidelity (fixture kata argv matching). | Tests 9 |
| M31 | Done tested only by implication. | Tests 12 |
| M32 | jq 1.6 needs `|=` on multiple paths (board-report:97) verified on jq 1.7 only. | Shell |

## DEFERRED (outside this branch; flagged, not patched here)

| # | Issue | Source | Reason |
|---|-------|--------|--------|
| D1 | Approvals live in the run dir the worker can write: a worker could forge `approved` (pre-existing design). | Security 1 | Document the trust level in README: approvals defend against model error, not a hostile worker. |
| D2 | Run dirs are 0755 until clean close. | Security 5 | Tracker. |
| D3 | `git add -A` at handoff (handoff-selected.sh:46-51) commits stray secrets. | Security 6 | Pre-existing script; separate change. |
| D4 | Agent-writable turn override file (continue-implement.sh:18-23). | Security 7 | Pre-existing. |
| D5 | No per-sweep spend cap. | Security 8 | Design question. |
| D6 | Publication target read from `selected.json` written before the agent ran. | Security 10 | Pre-existing; needs design. |
| D7 | SSH agent / gh credentials inherited; four-substring secret filter; KATA_AUTHOR passthrough. | Security 11 | Tracker + operator setup. |
| D8 | `${graph.workflow_dir}` spliced raw into `sh -c` commands. | Security 17 | Dippin/tracker; paths with quotes are unsupported today. |
| D9 | kata accepts `assign none` and makes an owner named none. | earlier | kata. |

### Tracker bugs to file upstream (never patched here)
1. `--no-tui` prints no tool stdout/stderr at all; only `status.json` has it.
2. A marker-less tool halt writes no checkpoint (`engine.go:657-661`), so `-r` fails on a first-node stop.
3. The engine never reads the `restart:` edge attribute and never resets the restart budget; the 51st loop fails the run.
4. SIGTERM is unhandled (no checkpoint flush); tool grandchildren in their own process group survive a cancel.
5. `PromptPlain` collapses all whitespace inside a line and wraps at 76.
6. Mode1 modal: Escape = default/first choice; a prompt taller than the terminal loses its top lines; ignores piped input on a TTY.
7. `<workdir>/.env` is loaded and `TRACKER_PASS_ENV=1` in it disables the secret filter.
8. Run dirs 0755 until close; every run also lands in `~/.local/state/tracker/runs` (2093 dirs, 2.0 GB).
9. Cancels are labelled timeouts in the summary.
10. Run dir is created lazily with the first artifact write.
11. Update check hits the network unless CI/TRACKER_NO_UPDATE_CHECK.
12. Console interviewer rejects choice keys and never re-prompts after an invalid answer.
