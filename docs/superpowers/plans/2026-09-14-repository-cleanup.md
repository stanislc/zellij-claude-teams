# Repository Cleanup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. Delegate only if the user requests parallel agent work.

**Goal:** Preserve the working #8/#9 startup and placement changes, complete safe command delivery and shared state handling, and reconcile the remaining PRs through independently verifiable changes.

**Architecture:** Retain the small Bash shim and FIFO-per-pane wrapper. Centralize only the command, capability, and state rules that must agree across handlers or shells. Keep the existing installation layout and make each integration produce a testable repository state.

**Tech Stack:** Bash 3.2+, zsh, Zellij CLI, optional fish, ShellCheck, a Bash regression harness with fake Zellij and real wrapper processes, GitHub Actions on macOS and Ubuntu.

---

## Evidence and scope

Read the [review and observations](../reviews/2026-09-14-pr-audit.md) first. The reviewed main is `93ed788`; local `maint/claude-code-2.1-compat` now contains it at `8e4e33d`. The earlier design remains in history but its pending-respawn, issue-closure, and no-live-Zellij assumptions are superseded.

This pass delivered the analysis and this plan. Implementation below is the proposed next work. No extra feature PR has been merged or edited on GitHub.

Use staged consolidation. A minimal late-input patch alone would leave the duplicated hardening and cross-shell state mismatch unresolved. A larger rewrite would discard useful working behavior and expand the review surface. The existing architecture is sufficient for this maintenance cycle.

Work in three reviewable integrations:

1. **Core stabilization:** tasks 1–4, incorporating shared #2/#5 work once.
2. **Fish:** task 5, based on the stabilized core and preserving #7 attribution.
3. **Additional capabilities:** task 6, taking #6's concerns separately.

Repository reconciliation and documentation finish each integration. Do not combine all four open PR heads into one unreviewed merge. No release tag is planned.

## Files and responsibilities

| File | Responsibility |
|---|---|
| `bin/tmux` | Parse supported tmux calls, validate targets, serialize launches, route Zellij operations |
| `bin/zellij-pane-wrapper` | Restore launch environment, receive one command, name the pane, manage process/state lifetime |
| `activate.sh`, `deactivate.sh` | Bash/zsh environment setup and safe state lifecycle |
| `activate.fish`, `deactivate.fish` | Equivalent fish contract when #7 lands |
| `functions/claude-zellij.fish` | Optional child-shell activation wrapper from #7 |
| `install.sh`, `install.fish` | Explicit, testable installation and removal under XDG paths |
| `tests/run.sh` | Test entry point and outcome reporting |
| `tests/helpers/fake-zellij` | Capability profiles, argument logs, real wrapper launch, injected failures |
| `tests/compat.sh`, `tests/state.sh`, `tests/fish.sh` | Protocol/targeting, state/shell lifecycle, and fish integration tests |
| `.github/workflows/test.yml` | Required cross-platform regression jobs |
| `README.md`, `CONTRIBUTING.md`, `CHANGELOG.md` | Supported behavior, reproducible checks, contribution rules, unreleased changes |

Do not extract a large framework. Add a shared state helper only if direct duplication would prevent bash and fish from using the same canonical algorithm; if introduced, it must be installed with the shim and tested from an installed copy.

## Task 1: Capture the passing compatibility baseline

**Files:** Create `tests/run.sh`, `tests/helpers/fake-zellij`, `tests/compat.sh`.

- [ ] Record the starting commit and clean tracked-file state. Keep local `.serena/` out of staging. Use a `stan/` branch for a new integration branch if one is needed.
- [ ] Reuse the assertion/runner ideas from #2, but create a capability-aware fake that actually starts `bin/zellij-pane-wrapper`; its old fake only creates sentinel files and is insufficient to prove command execution. The review-only probe demonstrates the required boundary.
- [ ] Give every case a fresh temporary root, a minimal child environment, a bounded timeout, and cleanup limited to processes and files created by that case. Do not capture the developer's real exported environment into fixtures.
- [ ] Add the following successful baseline cases with output assertions: deferred `split-window -- cat`; deferred `new-window -- cat`; legacy inline argv with spaces; split then FIFO send-keys; exact synthetic stdout; title precedence; two sibling agents; another leader group; killing one agent leaves another alive; rejected respawn after FIFO consumption.
- [ ] Exercise three capability profiles: neither targeted feature, no-focus only, and both no-focus plus targeted rename. The middle profile must take the legacy branch and preserve `new-window -n` naming.

The deferred-start case must drive this sequence, with its command writing a marker under the test root and remaining alive until cleanup:

```bash
"$shim" -S "$test_root/socket" split-window -d -t %0 -h -l 70% -P -F '#{pane_id}' -- cat
"$shim" select-pane -t %1 -T researcher
"$shim" set-option -p -t %1 remain-on-exit failed
"$shim" respawn-pane -k -t %1 -- "$test_command"
```

Required assertions: split prints exactly `%1`; no command or naming sentinel exists before respawn; the marker contains the expected bytes; first creation uses the leader ID; second uses the first live agent ID with direction down; a different leader uses its own ID with direction right.

- [ ] Run `/bin/bash tests/run.sh` on macOS and `bash tests/run.sh` with the newer Bash. Both must pass before committing `test: cover legacy and deferred teammate startup`.

## Task 2: Complete pane targeting and launch semantics

**Files:** Modify `bin/tmux`, `tests/helpers/fake-zellij`, `tests/compat.sh`.

- [ ] Add a failing test for FIFO-less `send-keys`: target `%7`, recorded Zellij ID `107`, and focus in another pane. Assert that the action names `107`, never uses an untargeted write on the modern profile, and does not change focus there.
- [ ] Add injected failures for missing/unknown IDs, failure to focus on legacy Zellij, and failure to write. Return nonzero, and never continue to a write after focus failure.
- [ ] Read and validate the recorded ID. Probe `write-chars --help` for `--pane-id` separately from the creation/rename capability, then dispatch along this structure:

```bash
if zellij action write-chars --help 2>/dev/null | grep -q -- '--pane-id'; then
    zellij action write-chars --pane-id "$zellij_id" "${COMMAND_TEXT}"$'\n' || exit 1
else
    zellij action focus-pane-id "$zellij_id" || exit 1
    zellij action write-chars "${COMMAND_TEXT}"$'\n' || exit 1
fi
```

Do not equate support for `rename-pane --pane-id` with support for targeted text writes. Do not blindly apply the old hardening fallback to modern Zellij.

- [ ] Add a target-aware `display-message -p '#{pane_id}' -t %N` test and incorporate #2's validated-target handling.
- [ ] Test a single compound command string separately from multiple literal arguments. For the latter, `printf %s 'two words'` must produce `two words`. Include an executable path containing spaces, empty arguments, shell metacharacters passed as data, and payload arguments named `-S` and `-L`.
- [ ] Stop stripping global socket options once the tmux subcommand is reached. Payload options must reach the handler unchanged. Use one command encoder for split/new-window/respawn, after the exact single-argument `cat` placeholder check:

```bash
encode_launch_command() {
    if [ "$#" -eq 1 ]; then
        printf '%s\n' "$1"
    else
        serialize_command "$@"
    fi
}
```

This preserves the single-string shell program and uses the existing `%q` serializer for literal argv. The [tmux command contract](https://man.openbsd.org/tmux#COMMANDS) makes that distinction. The prior August instruction to preserve unquoted `&&` tokens in all multi-argument calls must not override it.

- [ ] Return nonzero for a missing respawn target, empty command, absent FIFO, or already consumed FIFO. Add tests for each and for an invalid synthetic target. Use `printf '%s\n'` for FIFO writes so command text is not interpreted as echo options.
- [ ] Keep command delivery bounded when a FIFO exists without a living reader. Add a dead-wrapper fixture and a timeout assertion; verify any timeout path removes only state owned by that failed spawn.
- [ ] Run the full suite on both Bash versions and the disposable attached two-tab live scenario. Confirm that the late marker appears only in the target agent. Commit `fix: target pane input and preserve launch arguments`.

## Task 3: Consolidate #2/#5 state hardening and close lifecycle gaps

**Files:** Modify `activate.sh`, `deactivate.sh`, `bin/zellij-pane-wrapper`; create `tests/state.sh`; extend `tests/run.sh`. Add `bin/tmux` changes only where required for allocation/snapshot lifecycle.

- [ ] Use #2 as the canonical hardening source and retain attribution. The #5 tree is identical, so do not apply both. Resolve its `bin/tmux` conflict while preserving tasks 1–2 and all #8/#9 behavior.
- [ ] Add the six existing hardening tests, updating the late-write expectation to modern targeted writes with a separately tested legacy fallback. Make strict-shell fixtures explicitly test unset activation variables rather than silently masking shell failures.
- [ ] Add actual `zsh -f` tests for deactivation with zero and multiple PID files. Replace the unmatched glob using the same `command find` strategy already used in activation.
- [ ] Compute and validate root/session paths before exporting PATH, TMUX, or shim variables. Check directory creation, owner, permissions, and symlinks before any activation side effects. On rejection, a captured before/after environment must match.
- [ ] Use #2's deterministic session slug/hash contract in both supported shell families. Reject traversal or symlink escapes in cleanup using resolved paths, not merely a lexical string prefix. Test a forged outside path, a `..` path, root itself, an empty path, and a symlinked session child against sentinel files inside the temporary test directory.
- [ ] Ensure re-sourcing leaves exactly one shim PATH entry, including when it already appears later in PATH. Preserve the original environment needed for deactivation.
- [ ] Verify a new shell joining a live session does not remove another process's allocation lock or command environment snapshot. Use two controlled live test processes, overlapping startup, and assertions for unique pane IDs. Sweep only demonstrably stale owned state.
- [ ] Make all cleanup paths agree on pane-owned files, including `.title` and `.cmd`. Test early wrapper failure, command timeout, normal exit, and kill while waiting on the FIFO.
- [ ] Record whether deactivation is session-wide. Preserve that explicit contract for this integration; independent per-tab teardown is a separate feature unless the user chooses to expand scope.
- [ ] Run Bash and zsh tests, both capability profiles, and the two-tab regression sequence. Commit state work in focused stages, for example `fix: validate activation before exporting state` and `fix: preserve live session state during shell lifecycle`.

## Task 4: Establish the maintenance gate and reconcile core drafts

**Files:** Create `.github/workflows/test.yml`, `CONTRIBUTING.md`, `CHANGELOG.md`; modify `README.md` and remove genuinely unused helpers from `bin/tmux`.

- [ ] Remove the unused `stack_agent_panes` and `refocus_main` helpers and obsolete focus-chain comments. Remove unused parsed-value variables where options are intentionally ignored. Keep semantic fixes separate from cosmetic cleanup.
- [ ] Resolve actionable ShellCheck diagnostics. For intentional source-or-execute fallbacks, use narrow documented suppressions; do not disable a broad category to hide real failures.
- [ ] Add Ubuntu and macOS jobs. Install ShellCheck and zsh in the test environment; use macOS `/bin/bash` for the 3.2 compatibility gate and also run a current Bash. Add fish when task 5 is integrated. Run these checks:

```bash
for script in activate.sh deactivate.sh install.sh bin/tmux bin/zellij-pane-wrapper tests/run.sh tests/compat.sh tests/state.sh; do
    bash -n "$script" || exit 1
done
shellcheck activate.sh deactivate.sh install.sh bin/tmux bin/zellij-pane-wrapper tests/run.sh tests/compat.sh tests/state.sh
bash tests/run.sh
git diff --check
```

Parse each script separately: `bash -n file1 file2` only parses `file1`. Ensure the CI whitespace check covers the PR's actual base-to-head diff rather than only an empty checkout worktree.

- [ ] Test `install.sh` and uninstall using a temporary XDG data/runtime root, including paths with spaces. Validate the installed copy by launching the same protocol fixtures against it.
- [ ] Update the architecture diagram and configuration descriptions for both launch protocols, capability-based targeting, and the explicitly supported tmux subset. Distinguish locally tested Zellij 0.45.1 behavior, mock legacy profiles, and contributor-reported Claude versions.
- [ ] Add concise unreleased notes and the local development commands. Keep test commands, supported shell claims, and CI in agreement.
- [ ] Once the replacement core integration is verified and merged, mark #2/#5 superseded with its commit/PR and preserve attribution. #4 is already closed. Prepare any public message as a concrete draft; sending a GitHub message requires explicit user authorization.

**Core merge gate:** Linux/macOS jobs green, no unaddressed P1 review findings, passing installed-copy tests, and an attached two-tab smoke test. Report the lack of an authenticated local Claude conversation explicitly. An upstream release is a later decision.

## Task 5: Integrate fish from #7 against the stabilized contract

**Files:** Add `activate.fish`, `deactivate.fish`, `functions/claude-zellij.fish`, `install.fish`, `tests/fish.sh`; modify `install.sh`, `tests/run.sh`, CI, and README.

- [ ] Rebase #7 or transplant its scoped changes with attribution. The current conflict is README-only, but semantic state compatibility must still be fixed.
- [ ] Preserve its corrected checks-before-export behavior and optional on-demand wrapper. Adopt the same state root variable, slug/hash naming, containment checks, PATH deduplication, and live-lock policy as task 3.
- [ ] Run `fish --no-config` fixtures for outside-Zellij no-op, fresh activation, repeated activation, stale state, failed activation rollback, empty deactivation, and PATH restoration.
- [ ] Test bash and fish against the same session name and temporary runtime base; their resolved state paths must match. Verify that either shell can read valid state made by the other without destroying a live lock or pane.
- [ ] Test the `claude-zellij` wrapper using a stub executable that records argv/environment: outside Zellij, inside, already active, missing installation, quoted spaces, explicit teammate-mode override, and exit-status propagation. The parent fish environment must remain unchanged in on-demand mode.
- [ ] Test both installers, update-in-place, and uninstall under temporary XDG data/config roots. Check that the autoload function and installed helper files agree with documented paths.
- [ ] Run `fish --no-config -n` on each fish file plus full bash/zsh/fish CI. Merge fish only after these checks pass; local fish runtime testing was not possible during the audit.

## Task 6: Divide #6 into independent capabilities

**Files:** `bin/tmux`, targeted test cases, README, changelog. Use separate commits and preferably separate review units.

1. **Interrupts first.** Restore `if [ "$sk_send_sigint" = true ]; then`. Use an isolated process group containing a parent and child that record signal receipt. A plain C-c must cause the intended SIGINT behavior, produce no `write-chars`, and not affect any unrelated process. Verify the actual wrapper process-group arrangement before claiming descendant interruption.
2. **Capture next.** Probe the installed `dump-screen` interface. On capable Zellij, use the recorded target ID and propagate read failures. Cover missing/unknown targets, host `%0` mapping, empty and multiline output, preservation of trailing newlines, and no focus movement. Define the supported `-p` behavior and explicitly handle unsupported buffer/range semantics. The modern command was verified with Zellij 0.45.1; older support requires a validated adapter or a clear nonzero unsupported result.
3. **Layout last.** Retain `ZELLIJ_SHIM_LAYOUT=right|down` only with tests establishing first-agent override, second-agent stacking, and separate leader groups under #9's anchor logic. Remove the misleading promise that every agent follows the base override when subsequent panes are still forced down.

- [ ] Add a failing regression for each unit before changing its implementation, then run the full baseline. Recheck the actual PR diff after conflicts are resolved, especially around the no-op dispatch list.
- [ ] Reconcile #6 only after every retained component is accounted for. If capture or layout is deferred, leave that remaining work explicitly tracked instead of closing the entire contribution as completed.

## Completion checklist

- [ ] #8/#9 behavior remains covered and passing.
- [ ] Late input reaches its explicit pane without changing focus on capable Zellij.
- [ ] Command strings and argv preserve their respective semantics; invalid startup requests fail visibly.
- [ ] Bash 3.2/current Bash/zsh tests pass; fish tests pass once fish support is included.
- [ ] Shared state invariants and concurrent shell activation are tested.
- [ ] Linux/macOS CI and installed-copy checks pass.
- [ ] README, changelog, and contribution instructions match verified behavior.
- [ ] Every remaining PR has a clear incorporated/deferred/superseded disposition with attribution.
- [ ] No unrelated `.serena/`, runtime snapshots, credentials, or temporary state are staged.
- [ ] Public changes, local integration, test limitations, and any remaining feature work are accurately reported.
