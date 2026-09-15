# zellij-claude-teams

Use [Claude Code](https://docs.anthropic.com/en/docs/claude-code) **Agent Teams** inside [Zellij](https://zellij.dev) — no tmux required.

## The Problem

Claude Code's Agent Teams feature spawns each teammate in its own terminal pane using **tmux**. If you use Zellij as your terminal multiplexer, Agent Teams silently falls back to in-process mode — no split panes, no visual separation.

## The Solution

This project provides a **tmux shim** — a fake `tmux` binary that intercepts Claude Code's tmux commands and translates them to `zellij action` equivalents. Agent teammates spawn as real Zellij panes within your current tab.

```
┌──────────────────────┬──────────────────────┐
│                      │  researcher          │
│   Claude Code        ├──────────────────────┤
│   (your session)     │  implementer         │
│                      ├──────────────────────┤
│                      │  tester              │
└──────────────────────┴──────────────────────┘
```

Agent panes are named after their role and stack vertically on the right.

## Requirements

- **Zellij** 0.40+ (tested on 0.45.1). Focus-independent pane placement (multi-tab safe) needs 0.44.1+; older versions still work but place panes next to the focused pane.
- **Bash** 3.2+ for the shared runtime, including when your interactive shell is zsh or fish
- **Claude Code** with Agent Teams support (contributors report tests with 2.1.260 and 2.1.268; this release's checks use controlled stand-ins, not an authenticated conversation; see [Claude Code notes](#claude-code-notes))

## Installation

```bash
git clone https://github.com/stanislc/zellij-claude-teams.git
cd zellij-claude-teams
bash install.sh          # fish: fish install.fish
```

The install script copies files to `${XDG_DATA_HOME:-~/.local/share}/zellij-tmux-shim/` and prints the activation snippet for your shell.

Fish users can run `fish install.fish` to install the runtime and the optional `claude-zellij` launcher together. Neither installer edits your shell configuration.

### Shell activation

Add **one** of these to your shell config:

**Bash** (`~/.bashrc`):
```bash
if [ -n "$ZELLIJ" ]; then
    _shim="${XDG_DATA_HOME:-$HOME/.local/share}/zellij-tmux-shim/activate.sh"
    [ -f "$_shim" ] && . "$_shim"
    unset _shim
fi
```

**Zsh** (`~/.zshrc`):
```zsh
if [[ -n "$ZELLIJ" ]]; then
    _shim="${XDG_DATA_HOME:-$HOME/.local/share}/zellij-tmux-shim/activate.sh"
    [[ -f "$_shim" ]] && source "$_shim"
    unset _shim
fi
```

Then restart your shell inside Zellij.

### Fish

Run `fish install.fish` from the checkout, then use the installed function:

```fish
claude-zellij
claude-zellij --resume
```

The installer places `claude-zellij.fish` in fish's configuration directory under `functions/`. Inside Zellij, the function activates the shim in a child fish process, enables agent teams, and starts Claude with your arguments. It adds `--teammate-mode tmux` only when you have not supplied a teammate mode before `--`. The parent shell's environment stays unchanged. Outside Zellij, it calls Claude with your arguments unchanged. A missing installation produces a visible fallback message; a rejected activation stops the launch.

For activation throughout your fish shell, source the installed `activate.fish` or add this to `config.fish`:

```fish
if test -n "$ZELLIJ"
    set -l _shim "$XDG_DATA_HOME"
    test -n "$_shim"; or set _shim "$HOME/.local/share"
    set _shim "$_shim/zellij-tmux-shim/activate.fish"
    test -f "$_shim"; and source "$_shim"
end
```

With this alternative, set the Claude teams options described below yourself. Source the installed `deactivate.fish` to restore the saved environment. Deactivation closes the shim's remaining teammates across the current Zellij session, including teams in other tabs.

### Claude Code notes

- **Agent teams are gated.** Set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in the environment or add it under `"env"` in `~/.claude/settings.json`.
- **Since Claude Code 2.1.179 teammates run in-process by default** and never touch tmux, so nothing appears in Zellij even with the shim active. Set `"teammateMode": "tmux"` (or `"auto"`) in `~/.claude/settings.json`, or start Claude with `claude --teammate-mode tmux`.
- **Claude Code ≥ 2.1.2xx changed the spawn protocol**: the pane is created with a placeholder (`split-window … -- cat`), titled with `select-pane -T`, and the teammate is launched with `respawn-pane -k`. The shim supports this as well as the older `split-window` + `send-keys` sequence.

### Workspace trust (one-time)

Claude Code prompts for workspace trust per directory. To avoid each agent pane prompting individually, run `claude` once in your working directory and accept the trust dialog before using Agent Teams.

## Usage

Once activated, just use Claude Code normally inside Zellij:

```bash
claude           # start Claude Code
# Create a team → teammates appear as Zellij panes
```

The shim activates automatically when you're inside Zellij (it checks for the `$ZELLIJ` env var). Outside Zellij, it stays dormant.

### Deactivation

Use the path selected by your installer (the default is shown):

```bash
source ~/.local/share/zellij-tmux-shim/deactivate.sh
```

In fish, source `~/.local/share/zellij-tmux-shim/deactivate.fish`. The optional child-process launcher does not activate the parent shell. Manual deactivation restores the saved PATH and prior TMUX/TMUX_PANE values and closes remaining shim teammates for the current session.

### Updating

Deactivate existing teams, update your checkout, and rerun the installer you used:

```bash
git pull
bash install.sh          # fish: fish install.fish
```

The runtime uses its installed copy, so pulling alone does not update it. The fish installer also refreshes its autoloaded function; a new fish shell loads that updated function. Installers replace their own files, so keep custom edits separately.

### Uninstall

```bash
cd zellij-claude-teams
bash install.sh --uninstall
# Then remove the activation snippet from your shell config
```

If you used the fish installer, run `fish install.fish --uninstall` to remove the runtime and its `claude-zellij.fish` function. Other fish functions are preserved. Remove a startup snippet only if you added one.

## Configuration

| Variable | Default | Description |
|---|---|---|
| `ZELLIJ_TMUX_SHIM_DEBUG` | unset | Set to `1` to log all tmux calls to `$STATE_DIR/shim.log` |

## Features

- **Pane naming** — each agent pane is titled with its role (researcher, implementer, etc.) via `zellij action rename-pane`, which locks the title so Claude Code's TUI can't override it
- **Vertical layout** — the first agent splits right; subsequent agents stack below it automatically
- **Session isolation** — state is scoped by `ZELLIJ_SESSION_NAME`, so multiple Zellij sessions don't collide
- **Tab isolation** — agent teams in different tabs within the same session are tracked independently via `.group` files
- **Focus-independent placement** — panes are created relative to the Claude session that spawned them (`zellij action new-pane --no-focus`), not wherever your focus happens to be, and are renamed by pane id. You can keep working in another tab while a team spawns; nothing lands in the wrong tab and your focus never moves. Needs zellij 0.44.1+ (`new-pane --no-focus`, `rename-pane --pane-id`); older versions fall back to focus-based placement.
- **Targeted teammate input** — late `send-keys` calls use `write-chars --pane-id` when available, independently of the placement capabilities. Older versions focus the validated target before writing; failed focus or write operations return an error.

## How It Works

The shim uses a **FIFO-per-pane** architecture:

```
Claude Code                    Shim (bin/tmux)                 Zellij
───────────                    ───────────────                 ──────
tmux split-window -h ───────→  alloc pane ID (%1)
  (… -- cat placeholder         snapshot parent env
   is ignored)                  zellij new-pane ──────────────→ creates pane
                               wait for .ready sentinel        ↓
                                                               wrapper starts
                                                               creates FIFO
                                                               touches .ready
                               ← returns %1

tmux select-pane -t %1 -T name → record title for the wrapper

tmux send-keys -t %1 "cmd"  ─→ write "cmd" to FIFO
  or
tmux respawn-pane -k -t %1 -- "cmd"
                                                               wrapper reads FIFO
                                                               rename-pane (locks title)
                                                               touch .named sentinel
                               wait for .named
                                                               eval "$cmd"
                                                               (cmd runs in pane)

tmux kill-pane -t %1 ───────→ kill PID from .pid file
                                                               process exits
                                                               --close-on-exit
                                                               pane auto-closes
```

### Environment forwarding

Zellij's `new-pane` does **not** inherit the parent shell's environment (unlike tmux). The shim works around this by:

1. `snapshot_env()` captures the parent environment via `export -p` to a file
2. The pane wrapper restores it with `eval "$(cat parent.env)"`
3. Per-pane variables (`TMUX_PANE`, state dir) are overridden after restore

### Concurrency

- **Pane ID allocation** uses `mkdir`-based locking (portable; macOS lacks `flock`)
- Stale lock detection via PID-in-lockdir: if the locker process is dead, the lock is reclaimed
- Each pane's state is in separate files, so most operations are naturally isolated

## Troubleshooting

### Panes appear and disappear instantly

- **Stdout redirect**: The shim must never redirect the command's stdout. Claude Code checks `isatty(stdout)` and exits if it detects a pipe.
- **Workspace trust**: If you haven't accepted trust for the working directory, Claude Code exits immediately. Run `claude` once in that directory first.

### Agent panes open in the wrong tab or steal focus

On zellij versions without `new-pane --no-focus`, the shim can only open panes next to the *focused* pane, so switching tabs while a team spawns puts the pane in the tab you're looking at, and focus chains through the new panes. Upgrade zellij; with `--no-focus` support the shim places panes relative to the spawning session and never moves focus.

### Environment variables missing in panes

Ensure the shim is activated in your shell (check `echo $ZELLIJ_TMUX_SHIM_ACTIVE`). The shim snapshots your environment on first pane creation — variables set after activation but before the first `split-window` are captured.

### Debug logging

```bash
export ZELLIJ_TMUX_SHIM_DEBUG=1
# Use Claude Code normally, then inspect:
cat "${ZELLIJ_TMUX_SHIM_STATE}/shim.log"
```

## Known Limitations

- **No pane resizing** — Zellij manages layout automatically; tmux layout commands are no-ops
- **Fragile to Claude Code updates** — new tmux commands added upstream may need shim updates. Debug logging captures unhandled commands for diagnosis.
- **No real respawn** — `respawn-pane` is only supported for a pane still waiting for its first command (which is how Claude Code uses it). Respawning a pane that is already running a command returns an error instead of pretending to succeed.
- **Retained state limitations** — pane records use PIDs without process-birth identity. Older Zellij late-input fallback moves focus and can race a user changing it. See the [verification ledger](docs/verification/repository-stabilization.md) for scope and deferred work.

## Compatibility

| Platform | Status |
|---|---|
| macOS (Apple Silicon) | Tested |
| macOS (Intel) | Should work |
| Linux (x86_64) | Core and installed-copy tests pass on Ubuntu 24.04 CI; attached Zellij checked on macOS |
| Linux (ARM) | Should work |
| WSL2 | Untested, likely works |

The shim avoids GNU-specific extensions:
- `export -p` instead of `env -0` for environment capture
- `mkdir`-based locking with PID stale detection instead of `flock` or `find -mmin`
- Fractional `sleep` with integer fallback
- Runtime state in `$XDG_RUNTIME_DIR` (Linux) or `$TMPDIR` (macOS)

## Versions and development

The project release number is stored in `VERSION`, copied into the installation, and printed by `bash install.sh --version`. `tmux -V` reports a separate compatibility identity for Claude's tmux checks. See [the changelog](CHANGELOG.md), [release procedure](docs/RELEASING.md), and [verification ledger](docs/verification/repository-stabilization.md).

Deactivate existing teams before updating the installed scripts. Running wrappers and their FIFOs are not upgraded in place.

Tests require Python 3 and the actual shell being checked:

```bash
SHIM_TEST_BASH=/bin/bash tests/run.sh --suite core
SHIM_TEST_BASH=/bin/bash tests/run.sh --suite fish
SHIM_TEST_BASH=/bin/bash python3 tests/test_release.py
# Requires Zellij with targeted write/list/dump capabilities and an attached PTY:
SHIM_TEST_BASH=/bin/bash tests/run.sh --suite live --output /tmp/shim-live-result.json
```

The core fixture executes the real pane wrapper behind a fake Zellij command. The fish suite requires fish and uses isolated configuration/install directories. The live fixture creates and closes its own named session. CI checks system/current Bash on macOS and Bash on Linux; full Claude conversation testing is recorded separately from these stand-in commands.

Fish support is adapted from [Maxim Rubchinsky's #7](https://github.com/stanislc/zellij-claude-teams/pull/7), with lifecycle and launcher compatibility fixes against the maintained core.

## License

MIT
