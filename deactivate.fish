# deactivate.fish — Deactivate the zellij-tmux-shim in fish.
# Usage: source deactivate.fish
#
# Mirrors deactivate.sh.

function __zellij_tmux_shim_deactivate
    if test -z "$ZELLIJ_TMUX_SHIM_ACTIVE"
        echo "zellij-tmux-shim: not active, nothing to deactivate" >&2
        return 0
    end

    # Kill any remaining wrapper processes and clean up their panes
    if test -n "$ZELLIJ_TMUX_SHIM_STATE"; and test -d $ZELLIJ_TMUX_SHIM_STATE
        for pidfile in $ZELLIJ_TMUX_SHIM_STATE/*.pid
            set -l pid (cat $pidfile 2>/dev/null)
            if test -n "$pid"; and kill -0 $pid 2>/dev/null
                kill $pid 2>/dev/null
            end
        end
        rm -rf $ZELLIJ_TMUX_SHIM_STATE
    end

    # Restore original PATH
    if test -n "$ZELLIJ_TMUX_SHIM_ORIG_PATH"
        set -gx PATH $ZELLIJ_TMUX_SHIM_ORIG_PATH
    end

    # Unset all shim env vars
    set -e TMUX
    set -e TMUX_PANE
    set -e ZELLIJ_TMUX_SHIM_ACTIVE
    set -e ZELLIJ_TMUX_SHIM_DIR
    set -e ZELLIJ_TMUX_SHIM_STATE
    set -e ZELLIJ_TMUX_SHIM_REAL_TMUX
    set -e ZELLIJ_TMUX_SHIM_ORIG_PATH
    set -e ZELLIJ_TMUX_SHIM_DEBUG
    return 0
end

__zellij_tmux_shim_deactivate
set -l __zellij_tmux_shim_status $status
functions -e __zellij_tmux_shim_deactivate
test $__zellij_tmux_shim_status -eq 0
