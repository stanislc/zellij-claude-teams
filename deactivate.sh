#!/usr/bin/env bash
# Source this file to deactivate the zellij-tmux-shim.
# Usage: source deactivate.sh

if [ -z "$ZELLIJ_TMUX_SHIM_ACTIVE" ]; then
    echo "zellij-tmux-shim: not active, nothing to deactivate" >&2
    return 0 2>/dev/null || exit 0
fi

# Kill any remaining wrapper processes and clean up their panes
if [ -d "$ZELLIJ_TMUX_SHIM_STATE" ]; then
    for pidfile in "$ZELLIJ_TMUX_SHIM_STATE"/*.pid; do
        [ -f "$pidfile" ] || continue
        pid=$(cat "$pidfile" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
        fi
    done
    rm -rf "$ZELLIJ_TMUX_SHIM_STATE"
fi

# Restore original PATH
if [ -n "$ZELLIJ_TMUX_SHIM_ORIG_PATH" ]; then
    export PATH="$ZELLIJ_TMUX_SHIM_ORIG_PATH"
fi

# Unset all shim env vars
unset TMUX
unset TMUX_PANE
unset ZELLIJ_TMUX_SHIM_ACTIVE
unset ZELLIJ_TMUX_SHIM_DIR
unset ZELLIJ_TMUX_SHIM_STATE
unset ZELLIJ_TMUX_SHIM_REAL_TMUX
unset ZELLIJ_TMUX_SHIM_ORIG_PATH
unset ZELLIJ_TMUX_SHIM_DEBUG
