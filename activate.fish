# activate.fish — Activate the zellij-tmux-shim in fish.
# Usage: source activate.fish

function __zellij_tmux_shim_activate
    if test -z "$ZELLIJ"
        echo "zellij-tmux-shim: not inside zellij, skipping activation" >&2
        return 1
    end
    set -l data_home $XDG_DATA_HOME
    test -n "$data_home"; or set data_home $HOME/.local/share
    set -l shim_dir $data_home/zellij-tmux-shim
    if test -n "$ZELLIJ_TMUX_SHIM_ACTIVE"
        test -n "$ZELLIJ_TMUX_SHIM_DIR"; and set shim_dir $ZELLIJ_TMUX_SHIM_DIR
        set -l clean_path
        for component in $PATH
            test "$component" = "$shim_dir/bin"; or set -a clean_path "$component"
        end
        set -gx PATH "$shim_dir/bin" $clean_path
        return 0
    end

    set -l runtime_base $XDG_RUNTIME_DIR
    test -n "$runtime_base"; or set runtime_base $TMPDIR
    test -n "$runtime_base"; or set runtime_base /tmp
    set -l uid (/usr/bin/env PATH=/usr/bin:/bin id -u)
    or return 1
    set -l shim_root $runtime_base/zellij-tmux-shim-$uid
    set -l session_name $ZELLIJ_SESSION_NAME
    test -n "$session_name"; or set session_name default
    if test "$session_name" = .; or test "$session_name" = ..; or string match -q '*/*' -- "$session_name"
        echo "zellij-tmux-shim: ERROR: invalid zellij session name" >&2
        return 1
    end
    set -l state_dir $shim_root/$session_name

    set -l path_present 0
    set -q PATH; and set path_present 1
    set -l path_value (string join : -- $PATH)
    set -l tmux_present 0
    set -q TMUX; and set tmux_present 1
    set -l tmux_value "$TMUX"
    set -l pane_present 0
    set -q TMUX_PANE; and set pane_present 1
    set -l pane_value "$TMUX_PANE"
    set -l real_tmux (command -s tmux 2>/dev/null)

    set -lx PATH /usr/bin /bin
    if test -L "$shim_root"
        echo "zellij-tmux-shim: ERROR: state root is a symlink, refusing to activate" >&2
        return 1
    end
    if not command mkdir -m 700 -p "$shim_root"; or not command chmod 700 "$shim_root"
        echo "zellij-tmux-shim: ERROR: failed to create or secure state root" >&2
        return 1
    end
    set -l owner (command stat -c '%u' "$shim_root" 2>/dev/null)
    test -n "$owner"; or set owner (command stat -f '%u' "$shim_root" 2>/dev/null)
    if test "$owner" != "$uid"
        echo "zellij-tmux-shim: ERROR: state root not owned by current user" >&2
        return 1
    end
    if test -L "$state_dir"
        echo "zellij-tmux-shim: ERROR: session state is a symlink, refusing to activate" >&2
        return 1
    end
    if test -e "$state_dir"; and not test -d "$state_dir"
        echo "zellij-tmux-shim: ERROR: session state is not a directory" >&2
        return 1
    end
    if not command mkdir -m 700 -p "$state_dir"; or not command chmod 700 "$state_dir"
        echo "zellij-tmux-shim: ERROR: failed to create or secure session state" >&2
        return 1
    end
    set owner (command stat -c '%u' "$state_dir" 2>/dev/null)
    test -n "$owner"; or set owner (command stat -f '%u' "$state_dir" 2>/dev/null)
    if test "$owner" != "$uid"
        echo "zellij-tmux-shim: ERROR: session state not owned by current user" >&2
        return 1
    end
    if not test -e "$state_dir/next_id"
        printf '1\n' > "$state_dir/next_id"; or return 1
    end
    if not test -f "$state_dir/next_id"
        echo "zellij-tmux-shim: ERROR: next_id is not a regular file" >&2
        return 1
    end
    if not test -e "$state_dir/sessions"
        printf '' > "$state_dir/sessions"; or return 1
    end
    if not test -f "$state_dir/sessions"
        echo "zellij-tmux-shim: ERROR: sessions is not a regular file" >&2
        return 1
    end

    set -l has_live 0
    for pidfile in "$state_dir"/*.pid
        set -l pid (command cat "$pidfile" 2>/dev/null)
        if string match -rq '^[1-9][0-9]*$' -- "$pid"; and kill -0 "$pid" 2>/dev/null
            set has_live 1
            continue
        end
        set -l key (command basename "$pidfile" .pid)
        for ext in pid zellij_id fifo ready cmd named group title
            command rm -f "$state_dir/$key.$ext"; or return 1
        end
    end
    for idfile in "$state_dir"/*.zellij_id
        set -l key (command basename "$idfile" .zellij_id)
        test -f "$state_dir/$key.pid"; or command rm -f "$idfile"; or return 1
    end
    set -l lock_live 0
    if test -d "$state_dir/next_id.lock"; and not test -L "$state_dir/next_id.lock"
        set -l lock_pid (command cat "$state_dir/next_id.lock/pid" 2>/dev/null)
        if string match -rq '^[1-9][0-9]*$' -- "$lock_pid"; and kill -0 "$lock_pid" 2>/dev/null
            set lock_live 1
        end
    end
    if test $has_live -eq 0; and test $lock_live -eq 0
        command rm -f "$state_dir/parent.env"; or return 1
    end

    set -gx ZELLIJ_TMUX_SHIM_DIR "$shim_dir"
    set -gx ZELLIJ_TMUX_SHIM_STATE "$state_dir"
    set -gx ZELLIJ_TMUX_SHIM_REAL_TMUX "$real_tmux"
    set -gx ZELLIJ_TMUX_SHIM_SAVED_PATH_PRESENT $path_present
    set -gx ZELLIJ_TMUX_SHIM_SAVED_PATH_VALUE "$path_value"
    set -gx ZELLIJ_TMUX_SHIM_ORIG_PATH "$path_value"
    set -gx ZELLIJ_TMUX_SHIM_ORIG_PATH_SET $path_present
    set -gx ZELLIJ_TMUX_SHIM_SAVED_TMUX_PRESENT $tmux_present
    set -gx ZELLIJ_TMUX_SHIM_SAVED_TMUX_VALUE "$tmux_value"
    set -gx ZELLIJ_TMUX_SHIM_SAVED_TMUX_PANE_PRESENT $pane_present
    set -gx ZELLIJ_TMUX_SHIM_SAVED_TMUX_PANE_VALUE "$pane_value"
    set -l restored_path (string split : -- "$path_value")
    set -l active_path
    for component in $restored_path
        test "$component" = "$shim_dir/bin"; or set -a active_path "$component"
    end
    set -gx PATH "$shim_dir/bin" $active_path
    set -gx TMUX "zellij-shim:/tmp/zellij-shim,$fish_pid,0"
    set -gx TMUX_PANE %0
    set -gx ZELLIJ_TMUX_SHIM_ACTIVE 1
    return 0
end

__zellij_tmux_shim_activate
set -l __zellij_tmux_shim_status $status
functions -e __zellij_tmux_shim_activate
test $__zellij_tmux_shim_status -eq 0
