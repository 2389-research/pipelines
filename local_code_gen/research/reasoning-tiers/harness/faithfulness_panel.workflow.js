export const meta = {
  name: 'faithfulness-panel',
  description: 'Judge panel scoring each NIFB sprint-plan config (high/medium/low/hybrid) for faithfulness to the source spec',
  phases: [
    { title: 'Panel', detail: '4 plans x 3 faithfulness lenses, each judge reads the source spec as ground truth' },
    { title: 'Synthesize', detail: 'aggregate panel scores + consensus missed/invented per config' },
  ],
}

const SPEC = '/Users/michaelsugimura/Documents/GitHub/pipelines/experiments/NIFB/2026-03-06 Galaxy Digital Transcript.md'
const EMAIL = '/Users/michaelsugimura/Documents/GitHub/pipelines/experiments/NIFB/Email 1 - Galaxy Digital Thread (Feb 24-25, 2026).md'
const PLANS = [
  { key: 'high',   path: '/Users/michaelsugimura/Documents/GitHub/pipelines/experiments/nifb_upto_high/.ai/sprint_plan.md' },
  { key: 'medium', path: '/Users/michaelsugimura/Documents/GitHub/pipelines/experiments/nifb_upto_medium/.ai/sprint_plan.md' },
  { key: 'low',    path: '/Users/michaelsugimura/Documents/GitHub/pipelines/experiments/nifb_upto_low/.ai/sprint_plan.md' },
  { key: 'hybrid', path: '/Users/michaelsugimura/Documents/GitHub/pipelines/experiments/nifb_upto_hybrid/.ai/sprint_plan.md' },
]
const LENSES = [
  { key: 'completeness', focus: 'COMPLETENESS lens: your job is to find REAL requirements in the source spec that are MISSING or only weakly covered in the sprint plan. Be exhaustive about omissions. A requirement is "real" only if a reasonable reader finds it in the transcript/email as something the SOFTWARE SYSTEM must do.' },
  { key: 'scope_discipline', focus: 'SCOPE-DISCIPLINE lens: your job is to find sprints/requirements in the plan that DO NOT trace to the source spec — i.e. invented scope, OR action-items / research tasks / process notes / design principles that have been miscast as system features (e.g. "make a PII-free spreadsheet", "review the prototype", "intermediate milestone tests" as a feature). Splitting one real requirement into several finer ones is NOT a violation — only flag items with no real product-requirement basis in the spec.' },
  { key: 'holistic', focus: 'HOLISTIC FAITHFULNESS lens: judge overall how faithfully the plan represents the spec — neither missing real requirements nor inventing/miscasting non-requirements. Granularity (more FRs) is fine if each traces to a real requirement; judge fidelity, not count.' },
]
const SCHEMA = {
  type: 'object',
  properties: {
    faithfulness: { type: 'number', description: '0-10 overall faithfulness of this plan to the spec from your lens (10 = every real req covered, nothing invented/miscast)' },
    missed_real_requirements: { type: 'array', items: { type: 'string' }, description: 'real spec requirements missing/weak in this plan' },
    invented_or_miscast_items: { type: 'array', items: { type: 'string' }, description: 'plan items with no real product-requirement basis in the spec (invented scope, or action-items/process-notes miscast as features)' },
    notes: { type: 'string', description: 'one or two sentence rationale' },
  },
  required: ['faithfulness', 'missed_real_requirements', 'invented_or_miscast_items', 'notes'],
}

phase('Panel')
const jobs = PLANS.flatMap(p => LENSES.map(l => () =>
  agent(
    `You are a faithfulness judge applying ONE specific lens. Read the SOURCE SPEC (ground truth) and the candidate SPRINT PLAN, then judge the plan AGAINST the spec.\n\n` +
    `SOURCE SPEC (read both): \`${SPEC}\` and \`${EMAIL}\`\n` +
    `CANDIDATE SPRINT PLAN: \`${p.path}\`\n\n` +
    `Use the Read tool to read all three files in full before judging. Do NOT assume the plan's own requirement numbering is correct — verify each against the spec.\n\n` +
    `${l.focus}\n\n` +
    `Return your structured judgment. faithfulness is 0-10. Be concrete and specific in the lists (name the actual requirement or sprint item).`,
    { label: `${p.key}:${l.key}`, phase: 'Panel', schema: SCHEMA }
  ).then(v => ({ plan: p.key, lens: l.key, ...v })).catch(() => null)
))
const panel = (await parallel(jobs)).filter(Boolean)

// aggregate per plan in plain JS (no agent needed)
const byPlan = {}
for (const r of panel) {
  const b = (byPlan[r.plan] ||= { scores: [], missed: [], invented: [], lenses: {} })
  b.scores.push(r.faithfulness)
  b.missed.push(...r.missed_real_requirements)
  b.invented.push(...r.invented_or_miscast_items)
  b.lenses[r.lens] = { faithfulness: r.faithfulness, notes: r.notes }
}
const agg = {}
for (const [k, b] of Object.entries(byPlan)) {
  const mean = b.scores.reduce((a, c) => a + c, 0) / b.scores.length
  agg[k] = {
    mean_faithfulness: Math.round(mean * 10) / 10,
    per_lens: b.scores,
    n_missed_flags: b.missed.length,
    n_invented_flags: b.invented.length,
    lenses: b.lenses,
  }
}
log('Panel aggregate: ' + Object.entries(agg).map(([k, v]) => `${k}=${v.mean_faithfulness}/10 (missed:${v.n_missed_flags} invented:${v.n_invented_flags})`).join('  '))

phase('Synthesize')
const synthesis = await agent(
  `You are synthesizing a judge-panel faithfulness assessment of FOUR sprint-plan configs (high, medium, low, hybrid) produced from the same NIFB spec at different reasoning levels. Each config was scored by 3 independent judges (completeness, scope-discipline, holistic lenses) reading the source spec as ground truth.\n\n` +
  `Raw panel results (JSON):\n${JSON.stringify(panel, null, 2)}\n\n` +
  `Aggregate (JSON):\n${JSON.stringify(agg, null, 2)}\n\n` +
  `Produce: (1) a ranking of the four configs by faithfulness with mean scores; (2) for each config, the CONSENSUS missed real requirements (flagged by >=2 lenses or clearly real) and the CONSENSUS invented/miscast items; (3) a clear verdict on whether higher FR count correlated with worse faithfulness or not (the central open question); (4) a one-paragraph recommendation on which reasoning config to use for analyze_spec given that the tournament is reasoning-insensitive. Be concise and decisive.`,
  { phase: 'Synthesize' }
)

return { aggregate: agg, synthesis }
