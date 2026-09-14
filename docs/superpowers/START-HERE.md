# Repository stabilization: development handoff

**Planning status:** Complete documentation package. Development has not started.

This repository contains the decisions and evidence needed to close the planning conversation and start a separate development task. No chat history or temporary directory is required to understand the work.

## Read in this order

1. [Detailed design](specs/2026-09-14-repository-cleanup-design.md): required behavior, state/protocol interfaces, lifecycle, failure policy, and scope.
2. [Acceptance matrix](specs/2026-09-14-repository-cleanup-acceptance.md): named tests, observable outcomes, actual interpreter and live-PTY requirements.
3. [Execution plan](plans/2026-09-14-repository-cleanup.md): dependency order, file ownership, commit boundaries, and contribution reconciliation.
4. [PR selection](reviews/2026-09-14-pr-selection.md): comparison of #6–#9 and the decision to remove #2/#5 from the merge queue. [Audit](reviews/2026-09-14-pr-audit.md) and [evidence JSON](reviews/2026-09-14-pr-audit-evidence.json): behavior observed before fixes.
5. [Archived audit-source guide](reviews/2026-09-14-audit-sources/README.md): preserved reproduction sources, hashes, snapshot prerequisites, and limitations.

The detailed design governs proposed implementation; the plan sequences it. Audit results describe the old snapshot. The August design is historical where it conflicts. Planning completion must not be presented as completed development or a clean regression verdict.

## Exact starting state

| Item | Recorded value |
|---|---|
| Repository | `stanislc/zellij-claude-teams` |
| Local path used during planning | `/Users/stanislav/Projects/zellij-claude-teams` |
| Planning branch | `maint/claude-code-2.1-compat` |
| Reviewed upstream production main | `93ed78831b0745d0cfa3b33ba085298f8855ef93` |
| Local upstream integration | `8e4e33d69ee8a22580b049f8f65a874ed6ae65db` |
| Initial audit/plan commit | `80beff5` |
| Unrelated local content observed | Untracked `.serena/`; leave it alone |

The current documentation commit is the HEAD of the planning branch when this package is handed off. Inspect it with `git log -1`; do not hardcode a stale head from this text. Production files still match the reviewed main at planning completion. The GitHub inventory is a dated snapshot: #8/#9 merged; #2/#5 duplicated drafts; #6/#7 open with conflicts; #3 and issue #4 closed. Refresh before acting.

## Design decisions to retain

- Keep #8/#9; fix the reproduced late-input routing bug first.
- Retire #2/#5 as merge candidates while retaining independently verified hardening requirements. Their proposed withdrawal is not a completed GitHub closure.
- Use a shared Bash state helper and v2 namespace, per-pane environment, stable supervising wrapper, framed single-use delivery, and a durable acceptance receipt.
- Preserve session-wide deactivation, monotonic IDs, and private ownership checks. No hot upgrades or automatic stale-lock/legacy-state deletion.
- Enforce independent backend capabilities; prefer targeted operations. Preserve only the explicitly documented legacy fallback guarantees.
- Establish CI with the baseline harness, then integrate the core coherently. Fish follows the core contract and contains none of #6's additions. Include corrected #6 interrupt behavior before core acceptance, capture as a later feature, and layout as an optional independent unit; do not merge #6 unchanged.
- Record real versions and tests. Fish and authenticated Claude were unavailable during the audit; stand-in commands do not establish a full Claude conversation pass.

## First development actions

Inspect the working tree and read repository instructions. Refresh origin and PR heads, retaining the recorded hashes for comparison. If contributions have changed, review their new diff before using them. Start a `stan/` integration branch that carries these documentation commits; never reset user work to force the audit snapshot.

Begin at M0. Add tests/implementation only within the currently selected milestone and commit explicit owned files. Keep the v2 driver/wrapper/activation/installed-helper cutover coherent. Append actual new evidence to `docs/verification/repository-stabilization.md`; never change historical observations into apparent passing tests.

A suitable prompt for the next task is:

> Implement the core stabilization in `docs/superpowers/START-HERE.md` through the M3 core integration gate. Read the detailed design, acceptance matrix, and execution plan first. Refresh upstream/PR state and reconcile any drift from the recorded hashes. Work on a `stan/` branch carrying the planning documents, preserve unrelated `.serena/` and user changes, and use scoped commits. Follow the atomic v2 runtime/protocol transition, run the required Bash/zsh/Linux/macOS/installed-copy checks and attached Zellij smoke tests available in this environment, and record exact evidence and any unavailable gate. Stop with local commits and a concise implementation report; do not push, merge, close PRs, send GitHub messages, tag a release, or implement fish/capture/layout in this task.

That prompt deliberately requests the first integration only. A later task can authorize fish, capture/layout, or remote delivery after reviewing the core result. Do not claim the M3 gate passed if required CI or live evidence remains unavailable; report the exact remaining gate.

## Planning closeout

The package includes independent protocol/state/handoff review and corrected design contradictions about parser ordering, exec supervision, durable claims, receipt authentication after exit, lock ordering, and recovery. Documentation link/manifest/consistency checks validate the package; they do not validate unimplemented behavior.

No production changes, GitHub comments, additional PR merges, or release operations were performed while expanding this design. The conversation can be closed after the documentation commit is saved. The development milestones remain open in the execution plan.
