# activate.fish — Activate the zellij-tmux-shim in fish.
# Usage: source activate.fish
#
# Mirrors activate.sh. The shim's bin/tmux and pane wrapper are still bash
# scripts; fish only needs to export the same environment they expect.
#
# Body lives in a function so `return` works on every fish version, then the
# function is erased so nothing lingers in the shell.

function __zellij_tmux_shim_activate
    # Guard: only activate inside zellij
    if test -z "$ZELLIJ"
        echo "zellij-tmux-shim: not inside zellij, skipping activation" >&2
        return 1
    end

    set -l data_home $XDG_DATA_HOME
    test -n "$data_home"; or set data_home $HOME/.local/share

    # Guard: don't double-activate — but always re-ensure PATH priority.
    # Child shells inherit ZELLIJ_TMUX_SHIM_ACTIVE but rebuild PATH from
    # shell config, pushing the shim behind other entries (brew, cargo, etc.).
    if test -n "$ZELLIJ_TMUX_SHIM_ACTIVE"
        set -l shim_dir $ZELLIJ_TMUX_SHIM_DIR
        test -n "$shim_dir"; or set shim_dir $data_home/zellij-tmux-shim
        set -gx PATH $shim_dir/bin $PATH
        return 0
    end

    # Compute everything first and run the safety checks BEFORE exporting
    # anything, so a rejected activation leaves the shell untouched.

    # XDG-compliant install directory
    set -l shim_dir $data_home/zellij-tmux-shim

    # Runtime state goes in an ephemeral, per-user, per-session directory (PIDs, FIFOs, etc.)
    # XDG_RUNTIME_DIR is /run/user/UID on systemd Linux; TMPDIR is per-user on macOS
    # Scoped by ZELLIJ_SESSION_NAME so multiple zellij sessions don't collide.
    set -l runtime_base $XDG_RUNTIME_DIR
    test -n "$runtime_base"; or set runtime_base $TMPDIR
    test -n "$runtime_base"; or set runtime_base /tmp
    set -l shim_root $runtime_base/zellij-tmux-shim-(id -u)
    set -l session_name $ZELLIJ_SESSION_NAME
    test -n "$session_name"; or set session_name default
    set -l state_dir $shim_root/$session_name

    # Initialize state directory — this is the security keystone.
    # FIFOs, eval'd env files, and command delivery all live here.
    # chmod 700 MUST succeed; if it doesn't, the shim is unsafe.
    # Secure the per-user root directory first, then create the per-session subdir.
    if test -L $shim_root
        echo "zellij-tmux-shim: ERROR: state root is a symlink, refusing to activate" >&2
        return 1
    end
    if not mkdir -p $shim_root
        echo "zellij-tmux-shim: ERROR: failed to create state root $shim_root" >&2
        return 1
    end
    if not chmod 700 $shim_root
        echo "zellij-tmux-shim: ERROR: failed to secure state root $shim_root" >&2
        return 1
    end
    set -l owner (stat -c '%u' $shim_root 2>/dev/null; or stat -f '%u' $shim_root 2>/dev/null)
    if test "$owner" != (id -u)
        echo "zellij-tmux-shim: ERROR: state root not owned by current user" >&2
        return 1
    end
    # Per-session subdir inherits root's 700 protection
    if not mkdir -p $state_dir
        echo "zellij-tmux-shim: ERROR: failed to create state dir $state_dir" >&2
        return 1
    end

    # All checks passed — now change the environment.
    set -gx ZELLIJ_TMUX_SHIM_DIR $shim_dir
    set -gx ZELLIJ_TMUX_SHIM_STATE $state_dir

    # Save real tmux path before we shadow it (empty if tmux isn't installed)
    set -gx ZELLIJ_TMUX_SHIM_REAL_TMUX (command -v tmux 2>/dev/null)

    # Save original PATH for deactivation.
    # The name ends in PATH, so fish exports it colon-joined — the same
    # format activate.sh writes and deactivate.sh reads.
    set -gx ZELLIJ_TMUX_SHIM_ORIG_PATH $PATH

    # Prepend shim bin to PATH so our tmux shadows the real one
    set -gx PATH $ZELLIJ_TMUX_SHIM_DIR/bin $PATH

    # Set fake tmux env vars so Claude Code thinks it's inside tmux
    set -gx TMUX "zellij-shim:/tmp/zellij-shim,$fish_pid,0"
    set -gx TMUX_PANE '%0'

    # Initialize next_id counter (start at 1, %0 is reserved for the host pane)
    if not test -f $ZELLIJ_TMUX_SHIM_STATE/next_id
        echo 1 > $ZELLIJ_TMUX_SHIM_STATE/next_id
    end

    # Initialize sessions file
    if not test -f $ZELLIJ_TMUX_SHIM_STATE/sessions
        touch $ZELLIJ_TMUX_SHIM_STATE/sessions
    end

    # Sweep stale state from prior crashed sessions: remove state files
    # for PIDs that no longer exist. (An unmatched glob in `for` is silently empty.)
    for pidfile in $ZELLIJ_TMUX_SHIM_STATE/*.pid
        set -l pid (cat $pidfile 2>/dev/null)
        if test -n "$pid"; and not kill -0 $pid 2>/dev/null
            set -l key (basename $pidfile .pid)
            for ext in pid zellij_id fifo ready cmd named group
                rm -f $ZELLIJ_TMUX_SHIM_STATE/$key.$ext
            end
        end
    end

    # Clean up orphaned .zellij_id files (no matching .pid = dead pane)
    for idfile in $ZELLIJ_TMUX_SHIM_STATE/*.zellij_id
        set -l key (basename $idfile .zellij_id)
        test -f $ZELLIJ_TMUX_SHIM_STATE/$key.pid; or rm -f $idfile
    end

    # Remove stale env snapshot and lock from prior sessions
    rm -f $ZELLIJ_TMUX_SHIM_STATE/parent.env
    rm -rf $ZELLIJ_TMUX_SHIM_STATE/next_id.lock

    set -gx ZELLIJ_TMUX_SHIM_ACTIVE 1
    return 0
end

__zellij_tmux_shim_activate
set -l __zellij_tmux_shim_status $status
functions -e __zellij_tmux_shim_activate
test $__zellij_tmux_shim_status -eq 0
