# Repository Cleanup Implementation Plan

**Scope update, 2026-09-15:** The [selective maintenance plan](2026-09-15-selective-maintenance.md) supersedes this automatic M0–M6 sequence. This document is retained as a broader implementation option. Fish, #6 features, and the v2 transition are not mandatory current work. #2/#5 have since been closed and an update requested on #6; use the active plan for current disposition and authorization.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Checkboxes track development, which has not started. Follow the active task's delegation rules and assign nonoverlapping file ownership for parallel work.

**Goal:** Preserve #8/#9, complete safe command delivery and state handling, integrate fish, and account for each remaining contribution in reviewable stages.

**Architecture:** Keep the Bash/FIFO adapter and introduce one shared state helper, v2 runtime records, supervised command execution, and independent Zellij capability probes. The [detailed design](../specs/2026-09-14-repository-cleanup-design.md) governs implementation. The [acceptance matrix](../specs/2026-09-14-repository-cleanup-acceptance.md) defines test IDs and exact outcomes.

**Tech Stack:** Bash 3.2/current Bash, actual zsh, optional fish, Zellij CLI, standard macOS/Linux utilities, ShellCheck, GitHub Actions. Python is test tooling only.

---

## Before development

Begin from the current documentation head on local `maint/claude-code-2.1-compat`, containing production main `93ed788`, local integration `8e4e33d`, and first audit/plan commit `80beff5`. Read [START HERE](../START-HERE.md) for the fresh-task prompt. Do not begin from the superseded August commit.

- [ ] Inspect status and refs; preserve `.serena/` and unrelated changes.
- [ ] Fetch origin and relevant PR heads, compare them with the audit's exact hashes, and re-review changed contributions.
- [ ] Create/reuse a `stan/` integration branch carrying these documents; incorporate updated origin/main without discarding planning history or overwriting unrelated branch work.
- [ ] Confirm the implementation task's requested endpoint: local verified commits, draft PR, or another explicit delivery. Planning authorizes no remote publication or reconciliation.
- [ ] Create `docs/verification/repository-stabilization.md` for new results. Do not rewrite the historical audit JSON to imply fixes were already tested.

## Dependencies and integration boundaries

```text
M0 baseline harness + minimal CI
 -> M1 immediate routing/parser fixes
 -> M2a shared helper and isolated tests
 -> M2b atomic v2 driver/wrapper/shell cutover
 -> M2c lifecycle and terminal controls
 -> M3 core integration gate
      -> M4 fish
      -> M5 capture and layout, independently reviewable
 -> M6 contribution reconciliation: withdrawal or verified integration
```

M1 is an interim correctness patch, not the final stabilized core. Wire the v2 state and framed sender/receiver together in M2b; never deploy half the transition. Interim tests use fresh isolated state, and hot upgrades remain unsupported.

The interrupt portion of #6 moves into its own core commit in M2c because supervised execution must preserve terminal control. Capture is a useful later feature; layout is optional and independently deferrable. Fish depends on the frozen core state and installation interfaces and contains none of #6's additions. Neither #2 nor #5 is a merge dependency; see the [PR selection note](../reviews/2026-09-14-pr-selection.md).

## M0: Passing compatibility baseline and minimal CI

**Files:** Create `tests/run.sh`, `tests/helpers/fake-zellij`, `tests/compat.sh`, `.github/workflows/test.yml`, and the verification ledger.

- [ ] Implement runner selection/reporting, argument-preserving logs, watchdog cleanup, and independent capability profiles from the acceptance matrix.
- [ ] Derive cases from the acceptance matrix and launch the actual wrapper from fake Zellij. #2's assertions and archived audit sources are optional historical references, not merge dependencies or an unmodified maintained test suite.
- [ ] Add exactly these passing baseline cases: `protocol.deferred-split`, `protocol.deferred-window`, `protocol.inline-argv`, `protocol.fifo-send`, `protocol.synthetic-stdout`, `protocol.recorded-title`, `placement.first-leader`, `placement.next-live-sibling`, `placement.other-leader-anchor`, and `placement.capability-gate`. Full title/placeholder semantics and group-scoped listing enter at their fix milestones. Do not hide future failures as skipped baseline checks.
- [ ] Add Ubuntu/current Bash and macOS/system Bash 3.2/current Bash jobs. Enforce the selected interpreter in both shim and wrapper. Run syntax per file and PR base-to-head whitespace validation; report known ShellCheck baseline findings until the clean M3 gate.
- [ ] Run baseline locally, record versions/results, and commit `test: establish teammate protocol baseline and CI`.

**Gate:** Every implemented baseline case passes. Creating mock sentinels without executing the wrapper cannot satisfy the gate. Missing required interpreters fail their jobs.

## M1: Immediate late-input and parser correctness

**Files:** Driver, compatibility tests, fake Zellij.

- [ ] Reproduce targeted-late-write, legacy focus/write failure, display-target ordering, independent help probes, and payload socket-option cases.
- [ ] Implement targeted text writes with validated legacy focus fallback and failure propagation. Never retry a failed targeted operation against focus.
- [ ] Restrict global socket parsing to the prefix, retain query/control option ordering, explicitly reject unsupported input, and preserve documented compatibility no-ops.
- [ ] Separate raw single-string assignment from literal argv encoded with `command --` and `%q`. Verify spaces, empty arguments, metacharacters, and command-like argv[0]. Exact trailing-byte transport and durable acceptance belong to M2b.
- [ ] Use current-format target validation for this intermediate patch; full nonce/birth/schema identity becomes mandatory at M2b. Do not invent automatic legacy-state migration.
- [ ] Run baseline/new cases. Commit parser/encoding and targeting changes separately when each leaves tests passing.

**Gate:** The reproduced wrong-tab text-write bug is fixed on targeted backends, and payload options are preserved. Legacy focus limitations remain explicit.

## M2a: Shared state helper in isolation

**Files:** Create `libexec/zellij-shim-state`, `tests/state.sh`; extend runner/fixtures.

- [ ] Implement the sourceable/CLI boundary with `prepare`, `validate`, and `close`; sourcing must not alter caller shell state.
- [ ] Implement canonical v2 paths, slug/checksum/bytecount, raw-session collision checks, private object validation, and path restrictions.
- [ ] Implement metadata/group/focus mutexes separately from durable claims. Enforce lock order, bounded acquisition, matching-token release, and no automatic stealing.
- [ ] Implement monotonic reservation/phase operations, corruption/overflow rejection, process identity validation, owned-file cleanup, and receipt retirement.
- [ ] Test namespace/containment, concurrent allocation, pause-before-owner publication, identity mismatch, terminal receipt records, and rejected cleanup paths.
- [ ] Commit `feat: define shared v2 state operations`. Production continues using its old state until the coherent cutover; this helper-only commit changes no installed runtime contract.

**Gate:** Helper tests pass in both Bash versions. No production entry point depends on an absent installed helper.

## M2b: Atomic runtime, activation, and delivery cutover

**Files:** Driver, wrapper, bash/zsh adapters, installer, helper, compatibility/state tests.

- [ ] Wire all core entry points to the helper and install the complete manifest together. Require v2 schema/token validation and clearly reject inherited legacy activation.
- [ ] Make activation transactional, normalize PATH once, and preserve the initial restoration baseline across re-source.
- [ ] Snapshot exported environment per pane, preserve actual new-pane identity, validate restoration, and delete the restored snapshot.
- [ ] Pass the nonce last in wrapper argv and register PID/UID/birth/token. Keep the wrapper as a stable supervisor; payload exec/traps/options run in a child using the selected Bash.
- [ ] Serialize sibling creation and check reservations/registration against teardown. Preserve modern anchors and state the legacy placement limit.
- [ ] Add NUL framing, one durable claim, bounded reader/writer handling, atomic phase/result publication, and receipt authentication after process exit.
- [ ] Implement unknown-outcome diagnostics without retry/kill. Centralize transient cleanup and retained records; never reset IDs or recursively delete arbitrary state.
- [ ] Add all remaining argv/delivery cases, actual zsh lifecycle, snapshot isolation, exec supervision, concurrent creation/teardown, and receipt retirement. Prove partial framed input cannot run its initial marker command.
- [ ] Run every core case introduced through M2b and an installed-copy protocol smoke test; commit `feat: supervise framed launches in validated v2 state` as a coherent sender/receiver/runtime change. M2c adds terminal-control and remaining teardown cases before the complete M3 gate.

**Gate:** Baseline protocols pass; no mixed old/new state; incomplete delivery never executes; fast exits retain observable acceptance; core entry points agree on ownership and schema.

## M2c: Teardown and terminal controls

**Files:** Driver/helper/wrapper, state/compatibility tests; add `tests/live.sh` or a small test-only PTY runner.

- [ ] Complete session-wide closing, targeted pane close, bounded exit, owned-file cleanup, retained counters, and restoration on teardown failure.
- [ ] Correct C-c dispatch and use targeted byte 3 or the documented focus-plus-byte fallback. Do not port #6's broken boolean or negative-wrapper-PID assumption.
- [ ] Run attached canonical/raw PTY and unrelated-process tests; verify supervisor child cleanup. Record this as the incorporated interrupt portion of #6.
- [ ] Document and verify exact quiescent stale-mutex recovery, excluding durable launch claims and preserving counters/unrelated state.
- [ ] Commit lifecycle and terminal-control units separately when independently passing.

**Gate:** Shell lifecycle, cleanup/closing, and interrupt cases pass. No unverified process-group signalling fallback remains.

## M3: Core integration and maintenance gate

**Files:** CI, install fixtures, README, CONTRIBUTING.md, CHANGELOG.md, evidence ledger; narrow driver cleanup.

- [ ] Verify installed hashes/modes, spaced XDG paths, update/uninstall isolation, and full protocol execution without checkout helper fallback.
- [ ] Remove unused helpers/stale comments after behavior is covered. Resolve ShellCheck findings with narrow justified suppressions only.
- [ ] Require syntax, clean ShellCheck, full core suites, actual zsh, installed-copy tests, and PR-diff whitespace across Linux/macOS.
- [ ] Document the supported command/capability matrix, v2 upgrade/rollback, session-wide teardown, explicit recovery, and development commands. Add unreleased notes with attribution.
- [ ] Run all three live two-tab cases and interrupt PTY tests on the exact integration commit; record tool versions and observations.
- [ ] Review the final base-to-head diff and scoped staging. Check #2/#5's disposition; their proposed withdrawal does not require a replacement merge and does not retire the independently verified hardening requirements.

**Gate:** All required checks pass, no unresolved P1 finding, and complete installed-copy/attached live evidence. Report authenticated Claude testing separately; stand-ins do not satisfy it.

## M4: Fish from #7

**Files:** Fish adapters/function/installer, core installer, `tests/fish.sh`, CI and docs.

- [ ] Rebase/port the refreshed #7 head with attribution/relevant trailers and preserve its checks-before-export improvement.
- [ ] Use the shared helper and identical restoration/PATH rules; create no second state/hash/cleanup algorithm.
- [ ] Keep child-shell activation optional; detect explicit teammate-mode choice before adding a default. Preserve argv/environment/status and parent isolation.
- [ ] Test both installers and autoload management under temporary XDG config/data roots, without altering actual config.fish.
- [ ] Run every fish case with real fish on Linux/macOS, plus core regression. Record tested versions and any support floor established by evidence.
- [ ] Commit/review fish independently after the core interface freezes.

**Gate:** Bash/fish state and lifecycle agree; parent isolation and installed function update/uninstall are proven. Static review is insufficient.

## M5: Remaining #6 capabilities

**Files:** Driver, dedicated tests, README/changelog. Separate review units; no simultaneous shared-file editing without one owner.

- [ ] **Capture:** Implement only `-p [-t %N]` and optional `-S -`, targeted direct stdout, caller-default mapping, and visible unsupported/backend errors. Run capture plus core cases; commit independently.
- [ ] **Layout:** Implement exact first-agent environment/flag precedence and early invalid-value rejection. Preserve sibling down-stacking and independent groups. Run layout and live placement; commit independently.
- [ ] Record each component as incorporated or explicitly deferred. Do not close #6 merely because interrupts landed earlier.

**Gate:** Each retained feature passes its own contract and documentation. Deferred work remains visibly accounted for.

## M6: Contribution reconciliation

| Source | Verified original identity | Treatment |
|---|---|---|
| #2 `41a94a7` / #5 `ab9b063` | Stanislav Cherepanov; identical trees | Remove from merge queue; propose withdrawal; retain independently verified requirements |
| #6 `b71296f` | DeepTrial | Correct interrupt in core; add corrected capture later; keep layout optional; never merge this head unchanged |
| #7 `5120d78` | Maxim Rubchinsky; existing coauthor trailers | Preserve attribution/trailers when carrying original commits |
| #8/#9 | Already merged in the audited base | Preserve behavior and reference in maintenance notes |

- [ ] Use `cherry-pick -x` when retaining an original commit appropriately. Scoped rewrites name the source PR/hash and preserve author credit; do not misrepresent newly written tests as original contribution code.
- [ ] For incorporated work, prepare public messages with actual replacement PR/commit IDs and incorporated/deferred components. For withdrawn drafts, state withdrawal without inventing a replacement. Obtain authorization appropriate to remote actions in the implementation task.
- [ ] When the owner requests GitHub closure, close #2/#5 as withdrawn rather than implying their contents merged. Reconcile #7 after fish merges; reconcile #6 only when all components are merged or explicitly tracked. #3 and issue #4 are already closed in the audit snapshot.
- [ ] Finalize changelog, supported matrix, evidence ledger, and branch disposition. No release tag is planned.

## Completion distinction

Planning is complete when START HERE, detailed design, acceptance matrix, execution sequence, historical sources/manifest, and audit links are committed and consistent. Development checkboxes stay open until a future task performs the work.

Development completion requires the agreed integrations, named acceptance gates, scoped clean diffs, contribution disposition, and an honest account of unrun authenticated Claude/platform checks. Closing this conversation does not imply those later steps happened.
