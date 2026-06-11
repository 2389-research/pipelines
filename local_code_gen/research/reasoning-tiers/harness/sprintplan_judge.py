"""Pairwise blind judge of two sprint plans.
Paths are configurable (no machine paths baked in):
  argv[1]/argv[2]              plan A / plan B sprint_plan.md (default: high vs low under $REASONING_EXPERIMENTS_DIR)
  $REASONING_EXPERIMENTS_DIR   base dir for the defaults (default: ./experiments)
"""
import os, sys, json, anthropic
B = os.environ.get("REASONING_EXPERIMENTS_DIR") or os.path.join(os.getcwd(), "experiments")
PLAN_A = sys.argv[1] if len(sys.argv) > 1 else f"{B}/nifb_upto_high/.ai/sprint_plan.md"
PLAN_B = sys.argv[2] if len(sys.argv) > 2 else f"{B}/nifb_upto_low/.ai/sprint_plan.md"
hi=open(PLAN_A).read()
lo=open(PLAN_B).read()
A=anthropic.Anthropic()
RUB="""Two sprint plans (A and B) were produced from the SAME spec by the SAME pipeline, differing ONLY in reasoning_effort (one high, one low) — you are NOT told which is which. Judge them as decomposition artifacts that an architect will consume. Score each 0-5 on:
1. FR_COVERAGE — every functional requirement covered by some sprint, none orphaned.
2. SUBSYSTEM_COMPLETENESS — all real subsystems present (Raiser's Edge/CRM sync, waivers, orientation, check-in/QR, scheduling, messaging, donor matching, pathways).
3. SPRINT_SIZING — sprints roughly equal, well-scoped, sensible count (not too coarse/fine).
4. DEPENDENCY_ORDERING — foundations first, dependencies respected.
5. DOD_QUALITY — each sprint has concrete, testable Definition of Done.
6. ARCHITECT_READINESS — how cleanly an architect could turn this into a contract (clarity, no ambiguity).
Then: WINNER (A / B / TIE) and a one-line why, and any MISSING_REQUIREMENTS in either.
Strict JSON: {"A":{"fr_coverage":N,"subsystem_completeness":N,"sprint_sizing":N,"dependency_ordering":N,"dod_quality":N,"architect_readiness":N,"total":N},"B":{...},"winner":"","why":"","missing_A":"","missing_B":""}"""
msg=RUB+"\n\n===PLAN A===\n"+hi+"\n\n===PLAN B===\n"+lo
with A.messages.stream(model="claude-opus-4-6",max_tokens=3000,messages=[{"role":"user","content":msg}],extra_body={"thinking":{"type":"adaptive"},"output_config":{"effort":"high"}}) as s:
    r=s.get_final_message()
t="".join(b.text for b in r.content if getattr(b,"type","")=="text")
i,e=t.find("{"),t.rfind("}")
print(f"(A={PLAN_A}\n B={PLAN_B})\n")
try:
    v=json.loads(t[i:e+1]); print(json.dumps(v,indent=2))
except: print(t)
