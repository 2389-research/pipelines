# Releasing

## Versioning

This project follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html) from `v0.2.0` forward (the `v0.1.x` history is not retroactively re-versioned). The consumer surface is the set of `.dip` workflow files plus the `dev_loop/` operator-facing configuration shape.

**Operator surface — covered by SemVer:**

- `.dip` files (workflow names, presence, node graph, routing contract).
- `dev_loop/` YAML keys, environment-variable contract, and the conventions cascade.

**Internal — not covered:**

- `dev_loop/scripts/lib/*` helper APIs and other implementation internals; reserved to change without notice.

| Change | Bump |
| --- | --- |
| Add a node, edge, or optional field to a `.dip` (routing stays deterministic) | MINOR |
| Rename a node, remove a node, or change a routing contract operators depend on | MAJOR |
| Remove a `.dip` file | MAJOR |
| Rename a `.dip` file (e.g., `sprint_runner.dip` → `sprint_runner_v3.dip`) | MAJOR |
| Raise the minimum tracker pin (e.g., `v0.32.0` → `v0.35.0`) | MINOR — call out prominently in the changelog |
| Rename a `dev_loop/` YAML key or env var | MAJOR |
| Comment out a `dev_loop/` YAML default so auto-detection takes over (back-compatible) | MINOR |
| Bug fix with no surface change | PATCH |

The tracker-pin call is a known soft spot: a forward pin breaks operators stuck on the old tracker, which is exactly the consumer signal SemVer is meant to carry. Treating it as MAJOR would force a `1.0` discussion the project is not ready for, so it stays MINOR with a prominent changelog callout.

### Enforcement

Every PR that touches the SemVer surface (`*.dip` files, operator-facing `dev_loop/` configuration — `dev_loop/scripts/lib/` internals are excluded) must update `CHANGELOG.md` under `[Unreleased]`. The `changelog check` workflow enforces this by diffing the `[Unreleased]` section between base and HEAD, so touching the file for an unrelated reason (e.g., an old release note) does not satisfy the gate. Apply the `skip-changelog` label only for SemVer-surface PRs that legitimately need no entry (e.g., refactor-only / formatting / comment-only). PRs that only touch CI, docs, or internal helpers don't trigger the gate at all.

## Releases

Tagged releases live on the [GitHub releases page](https://github.com/2389-research/pipelines/releases) with full forensic notes (rationale, scope counts, process notes, known gaps). The short, scannable summary lives in [`CHANGELOG.md`](./CHANGELOG.md) at repo root, following [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format.

When cutting a new tag: move the `[Unreleased]` entries into a new dated version section, refresh the compare-link footers, and publish the long-form notes as a GitHub release.
