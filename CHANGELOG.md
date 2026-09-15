# Changelog

Project versions are independent of the tmux version reported by the compatibility shim.

## 0.2.0 — fish support

- Add native fish activation/deactivation, the optional `claude-zellij` child-shell launcher, and an installer that maintains the fish autoloaded function.
- Preserve explicit teammate-mode arguments and Claude's exit status; stop the launch when activation fails.
- Validate activation before changing the caller's environment, deduplicate the shim PATH entry, and restore saved PATH and TMUX values across Bash, zsh, and fish.
- Preserve live session records during activation and guard lifecycle cleanup paths and PIDs within the retained state format.
- Add real fish lifecycle, launcher, and isolated installer checks to macOS/Linux CI.

Adapted from Maxim Rubchinsky's [#7](https://github.com/stanislc/zellij-claude-teams/pull/7), source commit `5120d7896e85cae752589d16b08b1cbee0d0fd02`, with focused compatibility corrections. The shared Bash pane runtime retains the #8/#9 behavior and v0.1.1 fixes.

## 0.1.1 — compatibility maintenance

- Route late teammate input to its recorded pane on capable Zellij versions, with a checked legacy focus fallback and visible failures.
- Allow deactivation of an empty session in zsh without an unmatched-glob error.
- Add maintained wrapper/placement/input/shell regression tests and macOS/Linux CI.
- Add a project `VERSION` file, installed version metadata, and `bash install.sh --version`.

Validation and remaining limitations are recorded in `docs/verification/repository-stabilization.md`. This is a focused maintenance update, not the deferred state-format redesign.

## 0.1.0 — pre-maintenance baseline

Snapshot of main at `93ed78831b0745d0cfa3b33ba085298f8855ef93`, before the maintenance work.

- Includes #8's deferred teammate startup and pane naming.
- Includes #9's leader-relative placement and focus preservation.
- Retains the known late-input routing and empty-session zsh deactivation bugs, fixed in 0.1.1.
- Does not include fish support.
