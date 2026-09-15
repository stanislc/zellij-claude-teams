# deactivate.fish — Deactivate the zellij-tmux-shim in fish.
# Usage: source deactivate.fish

function __zellij_tmux_shim_deactivate
    if test -z "$ZELLIJ_TMUX_SHIM_ACTIVE"
        echo "zellij-tmux-shim: not active, nothing to deactivate" >&2
        return 0
    end
    set -l runtime_base $XDG_RUNTIME_DIR
    test -n "$runtime_base"; or set runtime_base $TMPDIR
    test -n "$runtime_base"; or set runtime_base /tmp
    set -l uid (/usr/bin/env PATH=/usr/bin:/bin id -u)
    or return 1
    set -l shim_root $runtime_base/zellij-tmux-shim-$uid
    set -l state_dir "$ZELLIJ_TMUX_SHIM_STATE"
    set -lx PATH /usr/bin /bin
    if test (command dirname "$state_dir") != "$shim_root"
        echo "zellij-tmux-shim: ERROR: unsafe session state path" >&2
        return 1
    end
    set -l tail (command basename "$state_dir")
    if test -z "$tail"; or test "$tail" = .; or test "$tail" = ..; or string match -q '*/*' -- "$tail"
        echo "zellij-tmux-shim: ERROR: unsafe session state path" >&2
        return 1
    end
    if test -L "$shim_root"; or test -L "$state_dir"; or not test -d "$shim_root"; or not test -d "$state_dir"
        echo "zellij-tmux-shim: ERROR: unsafe session state directory" >&2
        return 1
    end
    set -l owner (command stat -c '%u' "$shim_root" 2>/dev/null)
    test -n "$owner"; or set owner (command stat -f '%u' "$shim_root" 2>/dev/null)
    if test "$owner" != "$uid"
        echo "zellij-tmux-shim: ERROR: state root not owned by current user" >&2
        return 1
    end
    set owner (command stat -c '%u' "$state_dir" 2>/dev/null)
    test -n "$owner"; or set owner (command stat -f '%u' "$state_dir" 2>/dev/null)
    if test "$owner" != "$uid"
        echo "zellij-tmux-shim: ERROR: session state not owned by current user" >&2
        return 1
    end
    for pidfile in "$state_dir"/*.pid
        set -l pid (command cat "$pidfile" 2>/dev/null)
        if string match -rq '^[1-9][0-9]*$' -- "$pid"; and kill -0 "$pid" 2>/dev/null
            kill "$pid" 2>/dev/null
        end
    end
    command rm -rf "$state_dir"; or return 1

    if set -q ZELLIJ_TMUX_SHIM_SAVED_PATH_PRESENT
        if test "$ZELLIJ_TMUX_SHIM_SAVED_PATH_PRESENT" = 1
            set -gx PATH (string split : -- "$ZELLIJ_TMUX_SHIM_SAVED_PATH_VALUE")
        else
            set -e PATH
        end
    else if test "$ZELLIJ_TMUX_SHIM_ORIG_PATH_SET" != 0
        set -gx PATH $ZELLIJ_TMUX_SHIM_ORIG_PATH
    else
        set -e PATH
    end
    if test "$ZELLIJ_TMUX_SHIM_SAVED_TMUX_PRESENT" = 1
        set -gx TMUX "$ZELLIJ_TMUX_SHIM_SAVED_TMUX_VALUE"
    else
        set -e TMUX
    end
    if test "$ZELLIJ_TMUX_SHIM_SAVED_TMUX_PANE_PRESENT" = 1
        set -gx TMUX_PANE "$ZELLIJ_TMUX_SHIM_SAVED_TMUX_PANE_VALUE"
    else
        set -e TMUX_PANE
    end
    set -e ZELLIJ_TMUX_SHIM_ACTIVE ZELLIJ_TMUX_SHIM_DIR ZELLIJ_TMUX_SHIM_STATE
    set -e ZELLIJ_TMUX_SHIM_REAL_TMUX ZELLIJ_TMUX_SHIM_ORIG_PATH ZELLIJ_TMUX_SHIM_ORIG_PATH_SET
    set -e ZELLIJ_TMUX_SHIM_SAVED_PATH_PRESENT ZELLIJ_TMUX_SHIM_SAVED_PATH_VALUE
    set -e ZELLIJ_TMUX_SHIM_SAVED_TMUX_PRESENT ZELLIJ_TMUX_SHIM_SAVED_TMUX_VALUE
    set -e ZELLIJ_TMUX_SHIM_SAVED_TMUX_PANE_PRESENT ZELLIJ_TMUX_SHIM_SAVED_TMUX_PANE_VALUE
    set -e ZELLIJ_TMUX_SHIM_DEBUG
    return 0
end

__zellij_tmux_shim_deactivate
set -l __zellij_tmux_shim_status $status
functions -e __zellij_tmux_shim_deactivate
test $__zellij_tmux_shim_status -eq 0
