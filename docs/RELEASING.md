# Release versions and preparation

Use semantic project versions: patch releases for compatible fixes, minor releases for features such as fish support, and major releases for a deliberate breaking public contract. The pre-maintenance snapshot is `v0.1.0`; compatibility maintenance is `v0.1.1`; fish support uses `v0.2.0`.

`VERSION` is the project identity and is installed alongside the runtime. Inspect it with `bash install.sh --version` in a checkout or read the installed `VERSION` file. `tmux -V` intentionally retains the tmux protocol identity expected by callers; do not replace that output with the project release number.

For each release:

1. Complete the selected fixes/features and their relevant checks. Record the actual commit, platforms, shell versions, live checks, and limitations in `docs/verification/repository-stabilization.md`.
2. Update `VERSION` and `CHANGELOG.md` in a scoped commit. Keep compatibility fixes and fish integration separately reviewable.
3. Tag that immutable commit as `vX.Y.Z`. Do not move a release tag to hide a later change; increment the version instead.
4. Build the source archive with `git archive` from the tag, using a `zellij-claude-teams-X.Y.Z/` prefix. Compute a SHA-256 checksum and verify the archive's version and runtime file contents against that commit.
5. Prepare a GitHub draft release with the exact target commit, source archive, checksum, change summary, and known limits. Draft status means prepared, not published. Push only the selected review branch/tags needed for the prepared artifact; do not merge main or publish a release merely because a draft exists.
6. Read back the draft target and uploaded assets. Publishing a release is a separate explicit action; record its final URL and verify its tag when authorized.

The baseline `v0.1.0` is an exception to the VERSION-file requirement: its source archive deliberately preserves the exact older tree without adding metadata retroactively. The tag and release notes identify it. Existing teams must be deactivated before updating the installed shim; do not upgrade a running FIFO/wrapper session in place.
