# PR selection after the planning review

**Subsequent update, 2026-09-15:** The [active selective plan](../plans/2026-09-15-selective-maintenance.md) supersedes the proposed disposition below. #2/#5 are now closed, DeepTrial has been asked to revise #6 without a commitment to accept all features, and the owner has selected fish support from #7 after the focused compatibility fixes. The feature comparison and reviewed code observations below remain applicable to their recorded snapshots.

This note records the follow-up discussion about #6 versus #7/#8/#9 and withdrawing the owner's #2/#5 drafts. It updates the proposed PR disposition in the earlier [audit](2026-09-14-pr-audit.md); it does not change historical test results. GitHub heads and states were rechecked on 2026-09-14 and match the audited snapshots. No PR has been closed or merged during this follow-up.

## What each contribution adds

| Contribution | User-visible purpose | Relationship to the others |
|---|---|---|
| [#8](https://github.com/stanislc/zellij-claude-teams/pull/8), `6b80e863` | Starts teammates with the newer placeholder `cat` → title → `respawn-pane` protocol; fixes blank teammate panes | Core startup compatibility, already merged |
| [#9](https://github.com/stanislc/zellij-claude-teams/pull/9), `792e757d` | Creates and names teammates in their leader's tab while focus remains elsewhere; preserves sibling stacking | Builds on #8; already merged; does not add #6's controls |
| [#7](https://github.com/stanislc/zellij-claude-teams/pull/7), `5120d789` | Fish activation/deactivation, optional `claude-zellij` launcher, installation/update/uninstall integration | Adds a shell entry point; changes neither `bin/tmux` nor the pane wrapper. It contains none of #6's additions. Once integrated with main it uses the core behavior from #8/#9 |
| [#6](https://github.com/stanislc/zellij-claude-teams/pull/6), `b71296f6` | Pane-output capture, broader interruption, optional split orientation | Additional controls, independent of startup and fish. Its layout choice must preserve #9's leader anchor and sibling stacking |

## Include #6's features selectively

The recommendation is to include corrected interrupt and capture behavior, with layout as an optional later enhancement. Do not merge `b71296f6` unchanged or treat it as a replacement for #8/#9. Keep the contributor's credit when adapting the work.

| Component | Benefit | Current code and required treatment | Priority |
|---|---|---|---|
| `send-keys C-c` | Interrupt work in the intended pane, including foreground child processes | `bin/tmux:421` tests `$***` instead of the parsed `sk_send_sigint`. The prior audit reproduced the broken branch. Negating a wrapper PID also does not establish that it is the foreground process-group ID. Implement the design's targeted terminal byte handling and test canonical/raw PTY behavior | Core, M2c |
| `capture-pane -p -t %N` | Lets a caller read a teammate's terminal output/history instead of receiving the existing no-op result | Lines 674–708 silently accept unsupported options, always request full history, return success for missing targets/backend failures, and collapse trailing newlines through command substitution. Implement the explicit supported subset, target/capability validation, direct stdout, and visible failures | Useful follow-up, M5; not required for #8's startup fix |
| `ZELLIJ_SHIM_LAYOUT=right\|down` | Lets users choose the first teammate's split orientation | Preserve #9's leader-relative creation and down-stacking of later siblings. Validate configured values and document precedence over `-h/-v` | Optional, independently deferrable M5 unit |

This follow-up reviewed the exact code and current PR descriptions. It did not run new live tests or implement these fixes. The [acceptance matrix](../specs/2026-09-14-repository-cleanup-acceptance.md) specifies the required validation.

## How much weight to give contributor testing

Direct experience running Claude Code Agent Teams is valuable compatibility evidence. The PR records distinguish that evidence:

- #8 reports an actual Claude Code 2.1.268 conversation with two teammates, in addition to its wrapper harness.
- #9 reports a real Zellij two-tab check driven through the Claude startup sequence. Our earlier attached-Zellij audit corroborated placement/naming and exposed a remaining late-input routing bug.
- #7 reports real fish lifecycle tests and launcher tests against a stub Claude binary. Its current commit includes Claude coauthor trailers, but that does not make every execution path verified.
- #6 explicitly reports mock-Zellij checks and says a live end-to-end check was unavailable. Its current code still has the reproduced interrupt defect.

Choose contributions by useful behavior, reviewed implementation, and relevant test evidence. Whether Codex or Claude helped write a change does not establish its correctness. Contributor reports also remain distinct from checks independently run in this repository.

## Withdraw #2/#5 as merge candidates

The owner's preference is to retire [#2](https://github.com/stanislc/zellij-claude-teams/pull/2) and [#5](https://github.com/stanislc/zellij-claude-teams/pull/5). They have identical trees, stale assumptions, and conflicts against reviewed main. Remove both from the integration queue; do not merge either wholesale or require its merge before integrating community contributions.

Retain independently supported requirements: correct late-input targeting, PATH idempotence, activation failure rollback, safe state ownership/cleanup, and actual zsh lifecycle tests. The audit reproduced problems in current main; withdrawing drafts does not resolve those problems. Old code/tests may be consulted as historical references, with attribution if reused, but the new implementation is governed by the detailed design and acceptance cases.

The proposed GitHub disposition is to close the drafts as withdrawn when the owner requests that action. This does not require claiming a replacement has merged. Neither PR has been closed by this planning update.
