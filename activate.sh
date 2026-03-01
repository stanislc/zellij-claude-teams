#!/usr/bin/env bash
# Source this file to activate the zellij-tmux-shim.
# Usage: source activate.sh

# Guard: only activate inside zellij
if [ -z "$ZELLIJ" ]; then
    echo "zellij-tmux-shim: not inside zellij, skipping activation" >&2
    return 1 2>/dev/null || exit 1
fi

# Guard: don't double-activate
if [ -n "$ZELLIJ_TMUX_SHIM_ACTIVE" ]; then
    return 0 2>/dev/null || exit 0
fi

# XDG-compliant install directory
ZELLIJ_TMUX_SHIM_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/zellij-tmux-shim"

# Runtime state goes in a ephemeral, per-user directory (PIDs, FIFOs, etc.)
# XDG_RUNTIME_DIR is /run/user/UID on systemd Linux; TMPDIR is per-user on macOS
_runtime_base="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}"
ZELLIJ_TMUX_SHIM_STATE="${_runtime_base}/zellij-tmux-shim-$(id -u)"
unset _runtime_base

# Save real tmux path before we shadow it
ZELLIJ_TMUX_SHIM_REAL_TMUX="$(command -v tmux 2>/dev/null || true)"
export ZELLIJ_TMUX_SHIM_REAL_TMUX

# Save original PATH for deactivation
ZELLIJ_TMUX_SHIM_ORIG_PATH="$PATH"
export ZELLIJ_TMUX_SHIM_ORIG_PATH

# Prepend shim bin to PATH so our tmux shadows the real one
export PATH="${ZELLIJ_TMUX_SHIM_DIR}/bin:${PATH}"

# Set fake tmux env vars so Claude Code thinks it's inside tmux
export TMUX="zellij-shim:/tmp/zellij-shim,$$,0"
export TMUX_PANE="%0"

# Export state dir for shim scripts
export ZELLIJ_TMUX_SHIM_DIR
export ZELLIJ_TMUX_SHIM_STATE

# Initialize state directory — this is the security keystone.
# FIFOs, eval'd env files, and command delivery all live here.
# chmod 700 MUST succeed; if it doesn't, the shim is unsafe.
if [ -L "$ZELLIJ_TMUX_SHIM_STATE" ]; then
    echo "zellij-tmux-shim: ERROR: state dir is a symlink, refusing to activate" >&2
    return 1 2>/dev/null || exit 1
fi
mkdir -p "$ZELLIJ_TMUX_SHIM_STATE"
chmod 700 "$ZELLIJ_TMUX_SHIM_STATE"
# Verify ownership (guards against /tmp race where another user creates the dir first)
_owner=$(stat -f '%u' "$ZELLIJ_TMUX_SHIM_STATE" 2>/dev/null || stat -c '%u' "$ZELLIJ_TMUX_SHIM_STATE" 2>/dev/null)
if [ "$_owner" != "$(id -u)" ]; then
    echo "zellij-tmux-shim: ERROR: state dir not owned by current user" >&2
    return 1 2>/dev/null || exit 1
fi
unset _owner

# Initialize next_id counter (start at 1, %0 is reserved for the host pane)
if [ ! -f "$ZELLIJ_TMUX_SHIM_STATE/next_id" ]; then
    echo "1" > "$ZELLIJ_TMUX_SHIM_STATE/next_id"
fi

# Initialize sessions file
if [ ! -f "$ZELLIJ_TMUX_SHIM_STATE/sessions" ]; then
    touch "$ZELLIJ_TMUX_SHIM_STATE/sessions"
fi

# Sweep stale state from prior crashed sessions: remove state files
# for PIDs that no longer exist
for _pidfile in "$ZELLIJ_TMUX_SHIM_STATE"/*.pid; do
    [ -f "$_pidfile" ] || continue
    _pid=$(cat "$_pidfile" 2>/dev/null)
    if [ -n "$_pid" ] && ! kill -0 "$_pid" 2>/dev/null; then
        _key="${_pidfile##*/}"
        _key="${_key%.pid}"
        rm -f "$ZELLIJ_TMUX_SHIM_STATE/${_key}.pid" \
              "$ZELLIJ_TMUX_SHIM_STATE/${_key}.zellij_id" \
              "$ZELLIJ_TMUX_SHIM_STATE/${_key}.fifo" \
              "$ZELLIJ_TMUX_SHIM_STATE/${_key}.ready" \
              "$ZELLIJ_TMUX_SHIM_STATE/${_key}.cmd"
    fi
done
unset _pidfile _pid _key

# Remove stale env snapshot and lock from prior sessions
rm -f "$ZELLIJ_TMUX_SHIM_STATE/parent.env"
rm -rf "$ZELLIJ_TMUX_SHIM_STATE/next_id.lock"

export ZELLIJ_TMUX_SHIM_ACTIVE=1
