# decompose_gpt isolated harness

A 1:1 isolated reproduction of the `decompose_gpt` agent from
`spec_to_sprints.dip` (lines 156–198), wired to run standalone against a
pre-staged spec analysis.

## Why

The full `spec_to_sprints.dip` runs decompose_gpt inside a 3-way parallel
fan-out followed by 6 cross-critiques and a merge. To iterate on the
decompose_gpt prompt or measure its baseline cost/behavior, we need to run
*just that agent* against a fixed input.

This harness uses the actual tracker runtime (not a side-channel script), so
the result reproduces the production agent's tool environment exactly.

## What's identical to production

- Agent block (model, provider, reasoning_effort, reads/writes, prompt body)
  is byte-for-byte the same as `spec_to_sprints.dip:156-198`.
- Working dir contains `.ai/spec_analysis.md` and `.ai/drafts/` exactly as
  production does at the moment decompose_gpt runs.

## What differs

- `fallback_target: decompose_join` → `fallback_target: Exit` (the fan-in node
  doesn't exist here). Only matters on agent failure; happy path is unaffected.
- No upstream `analyze_spec` node — input is pre-staged from a known-good run
  (`experiments/NIFB/.ai/spec_analysis.md`).

## Layout

```
.ai/
  spec_analysis.md          # input — copied from experiments/NIFB
  drafts/                   # output dir (decompose_gpt writes decomposition_gpt.md here)
baseline/
  decomposition_gpt.md      # production output for the same input — diff target
  decomposition_claude.md   # sibling outputs from same NIFB run, for cross-model comparison
  decomposition_gemini.md
decompose_gpt_only.dip      # the harness pipeline
```

## Run

```bash
cd experiments/decompose_gpt_harness
tracker decompose_gpt_only.dip
```

After the run:

- New output: `.ai/drafts/decomposition_gpt.md`
- Run state: `.tracker/runs/<run_id>/decompose_gpt/{prompt.md,response.md,status.json}`
- Activity log: `.tracker/runs/<run_id>/activity.jsonl`

## Inspect a run

```bash
# Latest run id
RUN=$(ls -t .tracker/runs/ | head -1)

# Tool-call sequence
grep -E '^TURN |^TOOL CALL: ' .tracker/runs/$RUN/decompose_gpt/response.md

# Outcome + turn count
cat .tracker/runs/$RUN/decompose_gpt/status.json

# Token usage / model events (if logged)
grep -i 'token\|usage' .tracker/runs/$RUN/activity.jsonl
```

## Compare to baseline

```bash
diff -u baseline/decomposition_gpt.md .ai/drafts/decomposition_gpt.md | less

# Quick structural comparison
for f in baseline/decomposition_gpt.md .ai/drafts/decomposition_gpt.md; do
  echo "=== $f ==="
  echo "  sprints:  $(grep -c '^## SPRINT-' $f || grep -c '^### Sprint' $f)"
  echo "  FR refs:  $(grep -oE 'FR[0-9]+' $f | sort -u | wc -l | tr -d ' ')"
  echo "  DoD lines:$(grep -cE '^[0-9]+\.|^- \[ \]' $f)"
  echo "  bytes:    $(wc -c < $f | tr -d ' ')"
done
```

## Reset between runs

```bash
rm -rf .ai/drafts/* .tracker/
```

## Reference: production tool-call shape

For the original NIFB run, decompose_gpt completed in **4 turns** with this
sequence:

1. `read` → `.ai/spec_analysis.md`
2. `glob` → `**/*` (workspace scoping; not load-bearing)
3. `write` → `.ai/drafts/decomposition_gpt.md` (full markdown in one shot)
4. terminal text reply

Output was 14 sprints, ~20KB markdown.
