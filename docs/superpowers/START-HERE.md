# Repository maintenance: development handoff

**Status:** Selected development completed and independently reviewed on 2026-09-15. Compatibility maintenance and fish integration are implemented on `stan/compatibility-and-fish`. See the [verification ledger](../verification/repository-stabilization.md) for versioned results, release references, and limitations.

Start with the [selective maintenance plan](plans/2026-09-15-selective-maintenance.md). It governs current work and includes a fresh-task prompt. The earlier broad M0–M6 plan and v2 design are reference options; do not execute them automatically.

## Current decisions

- Keep merged #8/#9 and protect their startup, naming, placement, and focus behavior.
- #2/#5 are closed as outdated, withdrawn drafts. Independently reproduced bugs remain valid work candidates.
- DeepTrial has been [asked to update #6](https://github.com/stanislc/zellij-claude-teams/pull/6#issuecomment-5681941227). Review a revised contribution selectively; no commitment to include every feature.
- Fish support from #7 has been adapted onto the maintained core with contributor credit and real fish tests. The contributor's original PR has not been merged or closed by this work. Its functionality was not included by #8/#9.
- Both development stages are complete: the regression harness and focused late-input/zsh fixes, followed by fish integration and lifecycle corrections. The full v2 migration and #6 features remain deferred.

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

The table records the planning baseline. Development uses `stan/compatibility-and-fish`, carrying these documents. Inspect current git status and the verification ledger for newer production changes; do not reset user work to force the recorded snapshot. Use scoped commits and append results without rewriting historical evidence.

The historical audit did not have fish or an authenticated Claude executable. Development added real fish checks on macOS/Linux and attached Zellij checks. Harmless stand-in commands exercise the real wrapper/Zellij; an authenticated Claude conversation remains unverified. Record unavailable checks explicitly in future work.

## Closeout boundary

The planning package was committed before development. The exact baseline is preserved as `v0.1.0`; compatibility maintenance uses `v0.1.1`, and fish support uses `v0.2.0`. The review branch and draft release series provide the handoff. Main merges and release publication remain separate actions; no automatic monitoring was created.

This task can be closed after release preparation. Resume only for a selected new issue, contributor update, or merge/publication request. A fresh task can use the verification ledger and active plan without relying on this conversation.
