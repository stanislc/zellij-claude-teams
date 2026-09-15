# Claude Code 2.1 Compatibility Maintenance Design

> Historical design. The [2026-09-14 audit](../reviews/2026-09-14-pr-audit.md) and [cleanup plan](../plans/2026-09-14-repository-cleanup.md) supersede its execution assumptions: PRs #8/#9 are merged, issue #4 is closed, and a local Zellij smoke test is now available. The original text below is retained for context.

## Goal

Restore Agent Teams pane startup with current Claude Code while preserving the command paths used by older Claude Code versions. Consolidate the existing hardening work, add regression coverage and CI, update maintenance documentation, and merge the validated result to `main`. Do not tag or publish a GitHub Release in this work.

## Evidence and Scope

- `main` currently supports commands delivered directly by `split-window` or `new-window`, plus later `send-keys` calls.
- Issue #4 reports that Claude Code 2.1.190 and newer create a pane with a `cat` placeholder and later replace it through `respawn-pane`.
- The currently published npm versions observed during discovery were 2.1.221 (`latest`) and 2.1.220 (`stable`).
- Draft PRs #2 and #5 contain the same hardening commit. That commit adds state-path safety, target-aware command handling, and a Bash test harness.
- The repository has no tags, GitHub Releases, or CI workflow.

This maintenance cycle will not redesign pane layout, add new shells, change installation paths, or introduce a general tmux implementation.

## Compatibility Contract

The shim will support three agent-command delivery paths:

1. Legacy direct start: `split-window` or `new-window` includes the real agent command. The shim delivers it to the new pane wrapper immediately.
2. Current deferred start: `split-window` or `new-window` includes only the recognized `cat` placeholder. The shim leaves the wrapper waiting, and `respawn-pane -k -t %N -- <command>` delivers the real agent command.
3. Existing late input: `send-keys -t %N ... Enter` continues to deliver through the FIFO or, after startup, focuses the recorded Zellij pane before writing characters.

Unknown non-placeholder commands continue through the legacy direct-start path. A missing target, invalid synthetic pane ID, missing command, or unavailable FIFO must produce a debug entry and a nonzero exit when the requested operation cannot be completed.

## Implementation Design

### Baseline consolidation

Apply the shared PR #2/#5 hardening commit to the maintenance branch. Preserve its state-root containment, idempotent activation, target-aware `display-message`, focused late `send-keys`, and test harness. Resolve conflicts in favor of `main` behavior unless the hardening change has explicit regression coverage.

### Deferred-start recognition

Add a small predicate in `bin/tmux` that recognizes only the literal, single-argument `cat` placeholder. Both `split-window` and `new-window` use this predicate to decide whether to deliver a command immediately. Centralizing the rule prevents the two handlers from drifting.

### `respawn-pane` adapter

Add a dedicated handler that:

- accepts the tmux `-k` flag and requires `-t %N`;
- preserves all command arguments after `--` or the first non-option;
- validates the synthetic pane ID before constructing state paths;
- writes the reconstructed shell command to the existing per-pane FIFO;
- waits for the wrapper's naming sentinel so pane titles retain current behavior;
- fails clearly when the target, command, or waiting FIFO is absent.

Command reconstruction must preserve shell operators such as `&&` while safely quoting ordinary arguments. The implementation will reuse or extend one shared serializer rather than maintain incompatible command-joining rules across handlers.

### Tests and CI

Extend the Bash harness to cover:

- legacy direct command delivery;
- `cat` placeholder deferral;
- `respawn-pane` delivery to the intended pane;
- shell operators, whitespace, and quoted argument preservation;
- invalid targets, missing commands, and missing FIFOs;
- all existing hardening tests.

Add a GitHub Actions workflow for Ubuntu and macOS. It will run `bash -n`, ShellCheck, the Bash test harness, and `git diff --check`-equivalent whitespace validation where appropriate. Tests will use a fake `zellij` binary and temporary state; CI will not require an authenticated Claude session or a live Zellij UI.

### Documentation and release preparation

Update the README to:

- state the current tested Claude Code version and the retained legacy compatibility path;
- explain the deferred `respawn-pane` flow in the architecture section;
- document local development checks;
- replace stale limitations that claim current CLI behavior is unsupported.

Add concise release notes in a changelog for the first future tagged release. The notes will identify the compatibility restoration, hardening changes, tests, and known live-testing limits. This task will not create a tag or GitHub Release.

## GitHub Reconciliation

After verification, merge the maintenance branch to `main`. Close the duplicate draft PRs #2 and #5 with a pointer to the merged commit, and close issue #4 with the compatibility fix and verification summary. PR #3 remains closed and out of scope.

## Verification and Acceptance Criteria

The change is ready to merge when:

- syntax checks pass for every Bash script;
- ShellCheck passes for maintained shell files and tests;
- the full test harness passes on the local platform and in Linux/macOS CI, if CI is available before merge;
- the compatibility tests demonstrate both legacy and current startup protocols;
- no test or command writes outside its temporary state root;
- README and changelog claims match the commands actually verified;
- the working-tree diff contains no unrelated `.serena` or user-owned files.

Because this environment does not have an authenticated `claude` executable or an active Zellij session, a real interactive Agent Teams smoke test is not a merge prerequisite. That limitation must be stated in the merge summary.
