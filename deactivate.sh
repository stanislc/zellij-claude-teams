#!/usr/bin/env bash
# Source this file to deactivate the zellij-tmux-shim.
# Usage: source deactivate.sh

__zellij_tmux_shim_deactivate() {
    local _zct_runtime_base _zct_root _zct_state _zct_tail _zct_owner _zct_uid
    _zct_runtime_base=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
    _zct_uid=$(PATH=/usr/bin:/bin command id -u) || return 1
    _zct_root="${_zct_runtime_base}/zellij-tmux-shim-${_zct_uid}"

    if [ -z "${ZELLIJ_TMUX_SHIM_ACTIVE:-}" ]; then
        echo "zellij-tmux-shim: not active, nothing to deactivate" >&2
        return 0
    fi

    _zct_state=${ZELLIJ_TMUX_SHIM_STATE:-}
    case "$_zct_state" in
        "$_zct_root"/*) _zct_tail=${_zct_state#"$_zct_root"/} ;;
        *) echo "zellij-tmux-shim: ERROR: unsafe session state path" >&2; return 1 ;;
    esac
    case "$_zct_tail" in
        ''|.|..|*/*) echo "zellij-tmux-shim: ERROR: unsafe session state path" >&2; return 1 ;;
    esac
    if [ -L "$_zct_root" ] || [ -L "$_zct_state" ]; then
        echo "zellij-tmux-shim: ERROR: unsafe session state directory" >&2
        return 1
    fi
    _zct_cleanup=0
    if [ -e "$_zct_root" ]; then
        [ -d "$_zct_root" ] || { echo "zellij-tmux-shim: ERROR: unsafe state root" >&2; return 1; }
        _zct_owner=$(PATH=/usr/bin:/bin stat -c '%u' "$_zct_root" 2>/dev/null || PATH=/usr/bin:/bin stat -f '%u' "$_zct_root" 2>/dev/null)
        [ "$_zct_owner" = "$_zct_uid" ] || { echo "zellij-tmux-shim: ERROR: state root not owned by current user" >&2; return 1; }
        if [ -e "$_zct_state" ]; then
            [ -d "$_zct_state" ] || { echo "zellij-tmux-shim: ERROR: unsafe session state directory" >&2; return 1; }
            _zct_owner=$(PATH=/usr/bin:/bin stat -c '%u' "$_zct_state" 2>/dev/null || PATH=/usr/bin:/bin stat -f '%u' "$_zct_state" 2>/dev/null)
            [ "$_zct_owner" = "$_zct_uid" ] || { echo "zellij-tmux-shim: ERROR: session state not owned by current user" >&2; return 1; }
            _zct_cleanup=1
        fi
    fi

    if [ "$_zct_cleanup" -eq 1 ]; then (
        PATH=/usr/bin:/bin
        export PATH
        _zct_list="$_zct_state/.deactivate-pids.$$"
        find "$_zct_state" -maxdepth 1 -name '*.pid' -type f > "$_zct_list" || exit 1
        while IFS= read -r _zct_pidfile; do
            [ -n "$_zct_pidfile" ] || continue
            _zct_pid=$(cat "$_zct_pidfile" 2>/dev/null || true)
            case "$_zct_pid" in
                ''|0|0*|*[!0-9]*) continue ;;
            esac
            if kill -0 "$_zct_pid" 2>/dev/null; then kill "$_zct_pid" 2>/dev/null || true; fi
        done < "$_zct_list"
        rm -f "$_zct_list"
        rm -rf "$_zct_state"
    ) || return 1
    fi

    if [ -n "${ZELLIJ_TMUX_SHIM_SAVED_PATH_PRESENT+x}" ]; then
        if [ "$ZELLIJ_TMUX_SHIM_SAVED_PATH_PRESENT" = 1 ]; then export PATH=$ZELLIJ_TMUX_SHIM_SAVED_PATH_VALUE; else unset PATH; fi
    elif [ "${ZELLIJ_TMUX_SHIM_ORIG_PATH_SET:-1}" = 1 ]; then
        export PATH=${ZELLIJ_TMUX_SHIM_ORIG_PATH-}
    else
        unset PATH
    fi
    if [ "${ZELLIJ_TMUX_SHIM_SAVED_TMUX_PRESENT:-0}" = 1 ]; then export TMUX=$ZELLIJ_TMUX_SHIM_SAVED_TMUX_VALUE; else unset TMUX; fi
    if [ "${ZELLIJ_TMUX_SHIM_SAVED_TMUX_PANE_PRESENT:-0}" = 1 ]; then export TMUX_PANE=$ZELLIJ_TMUX_SHIM_SAVED_TMUX_PANE_VALUE; else unset TMUX_PANE; fi

    unset ZELLIJ_TMUX_SHIM_ACTIVE ZELLIJ_TMUX_SHIM_DIR ZELLIJ_TMUX_SHIM_STATE
    unset ZELLIJ_TMUX_SHIM_REAL_TMUX ZELLIJ_TMUX_SHIM_ORIG_PATH ZELLIJ_TMUX_SHIM_ORIG_PATH_SET
    unset ZELLIJ_TMUX_SHIM_SAVED_PATH_PRESENT ZELLIJ_TMUX_SHIM_SAVED_PATH_VALUE
    unset ZELLIJ_TMUX_SHIM_SAVED_TMUX_PRESENT ZELLIJ_TMUX_SHIM_SAVED_TMUX_VALUE
    unset ZELLIJ_TMUX_SHIM_SAVED_TMUX_PANE_PRESENT ZELLIJ_TMUX_SHIM_SAVED_TMUX_PANE_VALUE
    unset ZELLIJ_TMUX_SHIM_DEBUG
}

if __zellij_tmux_shim_deactivate; then
    unset -f __zellij_tmux_shim_deactivate
    return 0 2>/dev/null || exit 0
else
    unset -f __zellij_tmux_shim_deactivate
    return 1 2>/dev/null || exit 1
fi
