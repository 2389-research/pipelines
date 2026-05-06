# Qwen3.6:35b-a3b Hyperparameters

The Qwen team publishes specific sampling parameters for `qwen3.6:35b-a3b`. Wrong values produce textbook failure modes — endless repetition, chain-of-thought leaking into output files, off-trajectory generations.

## The recipe

| Stage | temperature | top_p | top_k | min_p | presence_penalty |
|---|---|---|---|---|---|
| Generate (initial / exploration) | 1.0 | 0.95 | **20** | 0 | **1.5** |
| Generate (modify / patch) | 0.6 | 0.95 | **20** | 0 | 0.0 |
| Syntax retry | 0.6 | 0.95 | **20** | 0 | 0.0 |
| LocalFix (SR blocks) | 0.6 | 0.95 | **20** | 0 | 0.0 |

**The pattern in one line:** `temp=1.0 + presence_penalty=1.5` for exploration with anti-repetition; `temp=0.6 + presence_penalty=0.0` for precise edits. **`top_k=20` always** — never 64 (which is what some Ollama configs default to).

## What goes wrong with bad values

- **`top_k=64`** (what we had before). Qwen ships with `top_k=20`; overriding to 64 makes the model wider-band and hurts coding tasks. **Single highest-leverage fix.**
- **`temp ≤ 0.2` with `top_p=0.95`**: effectively near-greedy on the dominant tokens. Qwen explicitly warns: "DO NOT use greedy decoding, as it can lead to performance degradation and endless repetitions." Failure mode: malformed SR blocks (repeated `=======` dividers, duplicated SEARCH sections), or single-file generations with repeated/broken structure.
- **No `presence_penalty`**: at temp=1.0, the model can spiral off into long tangents. We observed qwen writing its chain-of-thought as Python comments inside generated test files (~80 lines of "_let me think..._" prose embedded in `test_auth.py`). Adding `presence_penalty=1.5` to initial generation fixes this directly.
- **No `min_p`**: not strictly required, but Qwen's SWE-Bench harness sets it explicitly to 0.

## Thinking vs non-thinking mode

The 35B-A3B is hybrid. Recommended params CHANGE depending on which mode:

- `enable_thinking=true` (Ollama: `think:true`) — emits `<think>...</think>` blocks. Recipe: `temp=1.0, top_p=0.95`. Used by Qwen's own SWE-Bench harness for agentic coding.
- `enable_thinking=false` (Ollama: `think:false`) — no reasoning blocks. Recipe: `temp=0.7, top_p=0.8`.

**Mixing modes and params is a real footgun.** If the call uses `think:false` but `temp=1.0/top_p=0.95`, you've got non-thinking mode with thinking-mode params — a parameter mismatch.

The current `local_code_gen/sprint_runner_qwen.dip` uses `think:false` everywhere with the (mostly correct) thinking-mode-style params per the table above. Worth A/B testing flipping Generate(initial) and LocalFix to `think:true` since SWE work benefits from reasoning. Strip `<think>...</think>` blocks from the response before writing to file.

## How this lives in the dip

`local_code_gen/sprint_runner_qwen.dip` has FOUR qwen call sites with options blocks:

1. **Generate gen_file** (~line 119): initial-generation profile (temp=1.0, presence_penalty=1.5)
2. **Generate patch_file** (~line 142): modify-existing profile (temp=0.6, presence_penalty=0.0)
3. **Generate validate_and_retry** (~line 192): syntax-retry profile (temp=0.6, presence_penalty=0.0)
4. **LocalFix** (~line 500): SR-block profile (temp=0.6, presence_penalty=0.0)

All four were updated on Apr 30, 2026 with the values in the table above. Verify by running:

```bash
grep -nE "temperature|top_k|presence_penalty" local_code_gen/sprint_runner_qwen.dip | head -20
```

## Sources

- Qwen team's published recipe (cited in conversation 2026-04-30 by external research agent)
- Ollama default params for `qwen3.6:35b-a3b-q8_0` ship with `top_k=20` (so any dip overriding to 64 was producing worse-than-default output)

## When applying

When changing or adding qwen calls in any dip:

- Always set all five: `temperature, top_p, top_k, min_p, presence_penalty`.
- Pick from the table above based on the call's purpose.
- If `think:` mode changes, audit the temperature against the mode-specific recipe.
