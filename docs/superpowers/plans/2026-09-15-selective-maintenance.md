# Selective compatibility and PR maintenance plan

**Status:** Active plan as of 2026-09-15. PR administration below is complete; development has not started.

This plan supersedes the automatic M0–M6 progression in the [September 14 plan](2026-09-14-repository-cleanup.md). Keep contributions only when they solve a supported use case and pass relevant checks. The earlier v2 design is retained as an option, not a required migration or prerequisite for reviewing a contributor's focused fix.

## Verified decisions and actions

| Item | Current disposition | Next action |
|---|---|---|
| #8/#9 | Already merged; retain startup, naming, leader-relative placement, and focus behavior | Protect with regression checks; fix independently reproduced defects |
| [#2](https://github.com/stanislc/zellij-claude-teams/pull/2) / [#5](https://github.com/stanislc/zellij-claude-teams/pull/5) | Closed as withdrawn on 2026-09-15; neither merged | No port or replacement merge obligation; keep independently supported bug reports |
| [#6](https://github.com/stanislc/zellij-claude-teams/pull/6) | Open at `b71296f6fece8f2d96427ede5ecf2d2199a1aab4`; [update requested](https://github.com/stanislc/zellij-claude-teams/pull/6#issuecomment-5681941227) | Review a revised patch when available; no promise to include every feature |
| [#7](https://github.com/stanislc/zellij-claude-teams/pull/7) | Open at `5120d7896e85cae752589d16b08b1cbee0d0fd02`; deferred in this plan | Make a separate scope decision about fish support; do not close as already included |

Main was rechecked at `93ed78831b0745d0cfa3b33ba085298f8855ef93`. It has no `activate.fish`, `deactivate.fish`, `install.fish`, or `functions/claude-zellij.fish`. #8/#9 change the Bash core; they do not subsume #7's fish adapters and installation. Deferring fish does not prevent maintaining that core. A rejection needs a scope or implementation reason, rather than a claim that this functionality is already merged; it need not rule out future fish support.

The #2/#5 closure states and the exact posted #6 message were read back from GitHub. No branch was deleted, no code was pushed, and no further PR was merged. #7 received no closure or message. The old audit and its test evidence remain unchanged observations of the earlier snapshot.

## Next development task: focused compatibility fixes

1. Refresh repository instructions, origin, and relevant PR heads. Preserve unrelated `.serena/` content and user changes. Use a `stan/` branch carrying these planning documents.
2. Establish a compact maintained harness with the actual wrapper and independent Zellij capability fixtures. Cover the #8 deferred startup, legacy startup, recorded naming, #9 leader/sibling placement, and focus preservation. Use the earlier acceptance catalogue for case definitions, not as a requirement to implement all 77 cases.
3. Fix the reproduced late `send-keys` wrong-pane write. Prefer a validated explicit target; use the documented legacy focus fallback only when needed, propagate failures, and do not retry a failed targeted write against focus. Cover missing/stale targets and write/focus failures. Prove the marker reaches the intended teammate with focus in another tab.
4. Fix the reproduced empty-session zsh deactivation failure with a narrow change and real `zsh -f` tests. Check restoration and a populated controlled session. Do not rewrite the state format as part of this fix.
5. Run the maintained cases under Bash 3.2 and current Bash, actual zsh where relevant, an installed-copy startup smoke check, and an attached two-tab Zellij check. Add minimal CI for the selected cases on macOS/Linux. Record exact versions, commit, results, and unavailable checks in `docs/verification/repository-stabilization.md`. A mock or stand-in command is not an authenticated Claude conversation.
6. Stop with scoped local commits and evidence. Report the remaining audit findings separately. No automatic fish integration, #6 implementation, full parser expansion, v2 transition, push, merge, or release belongs to this task.

The remaining PATH, failed-activation, state/cleanup, and argument-contract findings stay in the [audit](../reviews/2026-09-14-pr-audit.md). Triage them by a concrete supported scenario, reproducer, impact, and smallest adequate fix. Closing the old drafts does not establish that those issues are fixed. A narrow patch must not be presented as complete state hardening.

## Reconsider #6 after an author update

The posted request asks DeepTrial to rebase on current main and preserve #8/#9, correct the parsed Ctrl-C flag and verify foreground-process behavior, make capture errors and unsupported operations explicit, preserve captured output, and move layout to a separate PR or omit it. Tests should distinguish mocks, real Zellij, and full Claude runs.

- **Interrupt:** accept only a correct target-specific implementation with real PTY evidence. The wrapper PID must not be assumed to be the foreground process-group ID. No text/empty-command fallthrough.
- **Capture:** accept only if a supported caller needs pane output and the declared subset has correct targeting, failure status, and output fidelity. Do not implement broad tmux capture emulation speculatively.
- **Layout:** deferred customization; no requirement to include it. Review separately if there is a concrete need.

A stale, uncorrected, or unnecessary component may be rejected. Re-review the new diff before deciding; the current head remains unsuitable for merging. Waiting for the contributor is not a commitment to repair or take over the entire PR. No automatic monitoring or follow-up schedule has been created.

## Fish and the earlier redesign

#7 is a separate optional feature. If fish support is selected, request or prepare an update against the then-current core and verify actual fish activation, restoration, launcher arguments/status, and installer behavior. If fish is outside scope, it can be closed with that explanation when the owner chooses. It is deferred for now.

The [detailed v2 design](../specs/2026-09-14-repository-cleanup-design.md), its [acceptance catalogue](../specs/2026-09-14-repository-cleanup-acceptance.md), and the former milestone plan remain reference material. Resume that architectural work only through an explicitly selected later scope. Do not partially adopt its wire/state format or impose it on #6/#7 merely because it was designed earlier.

## Fresh-task prompt

> Follow `docs/superpowers/START-HERE.md` and the active selective maintenance plan. Implement only the focused compatibility task: a maintained startup/placement regression harness, the reproduced late-input routing fix, and the empty-session zsh deactivation fix. Work on a `stan/` branch carrying the planning documents and preserve unrelated changes. Keep fixes scoped, verify the actual wrapper, relevant Bash/zsh variants, installed startup, and attached two-tab behavior, and record exact evidence and unavailable checks. Stop with local commits and a concise report. Do not begin the v2 redesign, implement fish or #6 features, push, merge, close PRs, send messages, or tag a release.
