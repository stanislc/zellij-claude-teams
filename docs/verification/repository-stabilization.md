# Repository stabilization evidence

Historical pre-fix results remain in [the September 14 audit](../superpowers/reviews/2026-09-14-pr-audit.md). This ledger records development checks separately.

## Version sequence

| Version | Scope | Reference |
|---|---|---|
| 0.1.0 | Exact pre-maintenance main, including #8/#9 and the known bugs | `93ed78831b0745d0cfa3b33ba085298f8855ef93`; annotated `v0.1.0` tag and verified GitHub draft |
| 0.1.1 | Late-input targeting, zsh empty deactivation, regression harness/CI, project version metadata | Compatibility-stage commit/tag, recorded when cut |
| 0.2.0 | Fish contribution updated against the maintained core | Planned next stage |

## Compatibility stage, 2026-09-15

- Test-first evidence: the initial core suite exposed eight failing methods for the intended routing, failure-handling, and zsh bugs, while six baseline methods passed. Review added a reproducer for PID `00` wrongly satisfying `kill -0` and a long-help-output probe incorrectly falling back under pipefail. Both failed before their fixes.
- Fresh core suite: **18/18 pass** under system Bash **3.2.57** and Homebrew Bash **5.3.15** on macOS arm64. The fake Zellij launches the actual wrapper using the selected absolute interpreter. Tests exercise modern/legacy creation, title/respawn, inline/FIFO startup, independent capability profiles, validated routing, failure propagation, and real zsh deactivation.
- Project version tests initially failed because VERSION was absent and `install.sh --version` installed files. The final **5/5 pass** under both Bash versions: semantic identity, read-only version output, installed manifest/modes, preserved tmux protocol identity, and deferred startup through the installed shebang and wrapper path.
- Attached **Zellij 0.45.1**: three live cases pass. Two agents execute and are named/stacked in the leader tab; the observer remains active; late input appears only in the first agent; killing it preserves the sibling/leader/observer and removes its state. Setup creates named tabs through acknowledged actions rather than relying on version-specific startup-layout behavior. The finalizer closes only the uniquely named test session.
- Syntax passes for the maintained Bash files under both interpreters. ShellCheck **0.11.0** has no error-severity findings; existing advisory warnings/information remain visible in CI. No claim of a fully warning-free or broadly hardened codebase is made.
- Independent core spec and code-quality reviews were performed. The malformed PID and help-probe findings were corrected and re-tested.

Commands: `SHIM_TEST_BASH=/bin/bash tests/run.sh --suite core`, repeat with `/opt/homebrew/bin/bash`; `python3 tests/test_release.py`; `tests/run.sh --suite live --output <controlled-result.json>`. CI runs selected core/release checks on Ubuntu and both system/current Bash on macOS. Remote run results and final release asset checks will be appended after verification.

## Limits and deferred work

No authenticated full Claude conversation was run; live cases use harmless controlled processes. Older Zellij capability profiles are simulated rather than installed end to end. PID reuse remains a limitation of the retained state format. The late-write fallback on older Zellij deliberately focuses the validated pane and still cannot prevent a user click racing the write. The broader state namespace, lock, environment-snapshot, and respawn serialization work remains outside this release scope. #6 is awaiting its author's update.
