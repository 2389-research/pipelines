# Pipeline notes

For the kata pipeline, Doctor Biz chose next ready, unowned selection,
exactly one item per run. Planning stays within that item. Reviews emulate
fresh-eyes checks with two different models and distinct expert roles.

Never create practice issues to probe kata. Inspect CLI help, source, or
existing records read-only. Isolate test state from the real daemon.

Kata runs may start on main in a repository without tracker ignore rules.
Prepare local artifact exclusions and a task branch automatically; preserve
unrelated uncommitted work and report its paths. Keep preflight failures on
ClaimNext rather than masking them with a generic Stop node.
