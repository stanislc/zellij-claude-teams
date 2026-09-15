# Repository maintenance: development handoff

**Planning status:** Complete handoff. Development has not started. The active scope was narrowed on 2026-09-15.

Start with the [selective maintenance plan](plans/2026-09-15-selective-maintenance.md). It governs current work and includes a fresh-task prompt. The earlier broad M0–M6 plan and v2 design are reference options; do not execute them automatically.

## Current decisions

- Keep merged #8/#9 and protect their startup, naming, placement, and focus behavior.
- #2/#5 are closed as outdated, withdrawn drafts. Independently reproduced bugs remain valid work candidates.
- DeepTrial has been [asked to update #6](https://github.com/stanislc/zellij-claude-teams/pull/6#issuecomment-5681941227). Review a revised contribution selectively; no commitment to include every feature.
- Fish support is selected. Keep #7 open as the source contribution, update it against the maintained core, and validate real fish behavior before integration. Its functionality was not included by #8/#9.
- Development has two reviewable stages: the regression harness and focused late-input/zsh fixes, then fish integration from #7. The full v2 migration and #6 features are outside this task.

## Read in this order

1. [Active selective maintenance plan](plans/2026-09-15-selective-maintenance.md): scope, completed GitHub actions, development sequence, and fresh-task prompt.
2. [Audit](reviews/2026-09-14-pr-audit.md) and [evidence JSON](reviews/2026-09-14-pr-audit-evidence.json): independently observed bugs, passing checks, and limitations.
3. [PR comparison](reviews/2026-09-14-pr-selection.md): what #6–#9 add and contributor testing evidence; its initial disposition is superseded by the active plan.
4. [Acceptance catalogue](specs/2026-09-14-repository-cleanup-acceptance.md): reusable named checks. Only cases relevant to selected work are required; the complete catalogue describes the earlier broad design.
5. [Archived audit-source guide](reviews/2026-09-14-audit-sources/README.md): preserved reproduction sources, hashes, snapshot prerequisites, and limitations.

The [v2 design](specs/2026-09-14-repository-cleanup-design.md) and [former execution plan](plans/2026-09-14-repository-cleanup.md) are available for a later explicit architectural decision. No chat history or temporary directory is required to understand the handoff.

## Starting state

| Item | Recorded value |
|---|---|
| Repository | `stanislc/zellij-claude-teams` |
| Local path used during planning | `/Users/stanislav/Projects/zellij-claude-teams` |
| Planning branch | `maint/claude-code-2.1-compat` |
| Reviewed and rechecked upstream production main | `93ed78831b0745d0cfa3b33ba085298f8855ef93` |
| Local upstream integration | `8e4e33d69ee8a22580b049f8f65a874ed6ae65db` |
| Unrelated local content observed | Untracked `.serena/`; leave it alone |

Inspect `git log -1` and status for the current documentation head. Production files still match the reviewed main at handoff. Refresh origin and PR heads before development; do not reset user work to force the recorded snapshot. Start a `stan/` branch carrying these documents, use scoped commits, and append new results to `docs/verification/repository-stabilization.md` without rewriting the historical evidence.

The audit did not have fish or an authenticated Claude executable available. Harmless stand-in commands exercised the real wrapper/Zellij, but do not establish a full Claude conversation pass. Record unavailable checks explicitly in future work.

## Closeout boundary

The planning package is committed independently from future development. The only remote actions during the September 15 update were the requested withdrawal of #2/#5 and update request on #6, verified after execution. No additional PR was merged, #7 remains open, and no development, push, release, or automatic monitor was started.

This conversation can be closed; a fresh task can start from the active plan and its prompt.
