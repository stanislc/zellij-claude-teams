# Repository stabilization evidence

Historical pre-fix results remain in [the September 14 audit](../superpowers/reviews/2026-09-14-pr-audit.md). This ledger records development checks separately.

## Version sequence

| Version | Scope | Reference |
|---|---|---|
| 0.1.0 | Exact pre-maintenance main, including #8/#9 and the known bugs | `93ed78831b0745d0cfa3b33ba085298f8855ef93`; annotated `v0.1.0` tag and verified GitHub draft |
| 0.1.1 | Late-input targeting, zsh empty deactivation, regression harness/CI, project version metadata | `d595bac82c7cf17272107c73cd09f2af528fffdc`; annotated `v0.1.1` tag |
| 0.2.0 | Fish contribution updated against the maintained core | Fish integration commit; tag prepared after final review and CI |

## Compatibility stage, 2026-09-15

- Test-first evidence: the initial core suite exposed eight failing methods for the intended routing, failure-handling, and zsh bugs, while six baseline methods passed. Review added a reproducer for PID `00` wrongly satisfying `kill -0` and a long-help-output probe incorrectly falling back under pipefail. Both failed before their fixes.
- Fresh core suite: **18/18 pass** under system Bash **3.2.57** and Homebrew Bash **5.3.15** on macOS arm64. The fake Zellij launches the actual wrapper using the selected absolute interpreter. Tests exercise modern/legacy creation, title/respawn, inline/FIFO startup, independent capability profiles, validated routing, failure propagation, and real zsh deactivation.
- Project version tests initially failed because VERSION was absent and `install.sh --version` installed files. The final **5/5 pass** under both Bash versions: semantic identity, read-only version output, installed manifest/modes, preserved tmux protocol identity, and deferred startup through the installed shebang and wrapper path.
- Attached **Zellij 0.45.1**: three live cases pass. Two agents execute and are named/stacked in the leader tab; the observer remains active; late input appears only in the first agent; killing it preserves the sibling/leader/observer and removes its state. Setup creates named tabs through acknowledged actions rather than relying on version-specific startup-layout behavior. The finalizer closes only the uniquely named test session.
- Syntax passes for the maintained Bash files under both interpreters. ShellCheck **0.11.0** has no error-severity findings; existing advisory warnings/information remain visible in CI. No claim of a fully warning-free or broadly hardened codebase is made.
- Independent core spec and code-quality reviews were performed. The malformed PID and help-probe findings were corrected and re-tested.

Commands: `SHIM_TEST_BASH=/bin/bash tests/run.sh --suite core`, repeat with `/opt/homebrew/bin/bash`; `python3 tests/test_release.py`; `tests/run.sh --suite live --output <controlled-result.json>`.

All three [hosted CI jobs](https://github.com/stanislc/zellij-claude-teams/actions/runs/34989943220) passed at `d595bac82c7cf17272107c73cd09f2af528fffdc`: Ubuntu 24.04 system Bash and macOS 15 system/current Bash. A fresh attached live run against that exact clean commit passed all three cases with cleanup exit 0. Source-archive contents were compared against the tag; archive SHA-256: `2a24d62596b043ce6c73ff0c6e37daa732b838d9698ab0d630f50348e422889a`.

The [v0.1.1 GitHub draft](https://github.com/stanislc/zellij-claude-teams/releases/tag/untagged-a974aaa8ee17103e55cd) was read back with `isDraft=true`, the exact commit target, and matching uploaded archive/checksum digests. The earlier [v0.1.0 draft](https://github.com/stanislc/zellij-claude-teams/releases/tag/untagged-818fd767e92d1f60f102) preserves pre-maintenance main. Its archive SHA-256 is `8bc79c9062d762cd270536482c93248bdcb6dab8fca6c6c74009c7ee717f6cef`.

## Fish integration, 2026-09-15

The source contribution is Maxim Rubchinsky's #7 at `5120d7896e85cae752589d16b08b1cbee0d0fd02`. It adds shell adapters and installation around the existing Bash pane runtime. The port retains that boundary and includes necessary lifecycle and launcher corrections; it does not adopt the deferred v2 state design.

Real-fish preflight of the source contribution reproduced repeated PATH entries, lost prior TMUX values, empty-PATH restoration failure, and successful activation despite state initialization failure. The new test-first suite against v0.1.1 (which has no fish files) initially produced 22 assertion failures and one error across 13 methods. Fish's native empty-PATH representation was then reflected in the fixture: capture the baseline inside fish and compare restoration to it, while Bash retains exact empty-component checks.

The core deactivation fixture now uses the retained canonical runtime/user/session state directory so it exercises valid cleanup under the new path guard. Existing behavior assertions remain. A real `zsh -f` lifecycle case also checks repeated activation and restoration of the shared shell adapter.

Further targeted RED/GREEN cases cover inherited activation with a rebuilt PATH in the optional launcher, a living allocator-lock owner before any pane PID exists, and preservation of the fish caller's umask. The launcher now activates in its child for both fresh and inherited-active calls. Activation preserves snapshots for a live allocation and leaves lock recovery to the existing allocator.

Local results: **16/16 fish, 18/18 core, and 5/5 release/installed-copy tests pass** under both Bash 3.2.57 and 5.3.15 with fish 4.9.3. The fish suite invokes real fish with isolated HOME/XDG/config/runtime roots, an argv/status-recording Claude stand-in, and installed deferred startup through the actual shared wrapper. Bash, zsh, and fish parsing checks, ShellCheck at error severity, and changed-line whitespace checks pass. Hosted fish results and release verification are recorded at closeout.

The first integration [CI run](https://github.com/stanislc/zellij-claude-teams/actions/runs/34993210305) at `df64a7e74652714ec95b7c7cd4890a5bcc805a35` passed all three jobs, including fish 3.7.0 on Ubuntu and fish 4.9.2 on macOS. Its exact clean checkout also passed all three attached Zellij checks. Independent spec review then identified two missing cases despite the green suite: deactivating another shell after shared state removal, and restoring a genuinely unset global fish PATH.

Both review findings were reproduced before fixing them. Deactivation now skips cleanup for absent canonical state while retaining unsafe-object rejection, and fish explicitly erases global PATH when restoring an unset baseline. The expanded suite also persists six inherited Bash-to-fish/fish-to-Bash TMUX/PANE restoration cases. Fresh local verification after the fixes: **20/20 fish, 18/18 core, and 5/5 release tests under each Bash interpreter**, plus parsing, ShellCheck error severity, and whitespace checks.

## Limits and deferred work

No authenticated full Claude conversation was run; live cases use harmless controlled processes. Older Zellij capability profiles are simulated rather than installed end to end. PID reuse remains a limitation of the retained state format. The late-write fallback on older Zellij deliberately focuses the validated pane and still cannot prevent a user click racing the write. The broader state namespace, lock, environment-snapshot, and respawn serialization work remains outside this release scope. #6 is awaiting its author's update.
