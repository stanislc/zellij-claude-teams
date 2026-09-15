# Changelog

Project versions are independent of the tmux version reported by the compatibility shim.

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
