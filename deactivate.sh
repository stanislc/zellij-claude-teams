#!/usr/bin/env bash
# shellcheck disable=SC2317
# Source this file to deactivate the zellij-tmux-shim.
# Usage: source deactivate.sh

if [ -z "${ZELLIJ_TMUX_SHIM_ACTIVE:-}" ]; then
    echo "zellij-tmux-shim: not active, nothing to deactivate" >&2
    return 0 2>/dev/null || exit 0
fi

# Kill any remaining wrapper processes and clean up their panes.
# Refuse cleanup if the state path is not inside the activation-created root.
_state_dir="${ZELLIJ_TMUX_SHIM_STATE:-}"
_state_root="${ZELLIJ_TMUX_SHIM_ROOT:-}"
if [ -n "$_state_dir" ]; then
    if [ -z "$_state_root" ]; then
        echo "zellij-tmux-shim: ERROR: state root missing, refusing cleanup" >&2
        unset _state_dir _state_root
        return 1 2>/dev/null || exit 1
    fi
    case "$_state_dir" in
        "$_state_root"/*) ;;
        *)
            echo "zellij-tmux-shim: ERROR: state dir outside state root, refusing cleanup" >&2
            unset _state_dir _state_root
            return 1 2>/dev/null || exit 1
            ;;
    esac
fi

if [ -d "$_state_dir" ]; then
    for pidfile in "$_state_dir"/*.pid; do
        [ -f "$pidfile" ] || continue
        pid=$(cat "$pidfile" 2>/dev/null)
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null
        fi
    done
    rm -rf "$_state_dir"
fi
unset _state_dir _state_root

# Restore original PATH
if [ -n "${ZELLIJ_TMUX_SHIM_ORIG_PATH:-}" ]; then
    export PATH="$ZELLIJ_TMUX_SHIM_ORIG_PATH"
fi

# Unset all shim env vars
unset TMUX
unset TMUX_PANE
unset ZELLIJ_TMUX_SHIM_ACTIVE
unset ZELLIJ_TMUX_SHIM_DIR
unset ZELLIJ_TMUX_SHIM_ROOT
unset ZELLIJ_TMUX_SHIM_STATE
unset ZELLIJ_TMUX_SHIM_REAL_TMUX
unset ZELLIJ_TMUX_SHIM_ORIG_PATH
unset ZELLIJ_TMUX_SHIM_DEBUG
